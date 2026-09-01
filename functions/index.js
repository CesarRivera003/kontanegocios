const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require('crypto');

admin.initializeApp();

// Configuración: Usamos la región por defecto
setGlobalOptions({ region: "us-central1" });

// ==================================================================
// 🔑 CONFIGURACIÓN MAESTRA DE PLEMSI (MARCA BLANCA / DISTRIBUIDOR)
// ==================================================================
// Aquí está tu llave. Cuando la DIAN te apruebe, solo cambias este texto por el nuevo.
const PLEMSI_MASTER_API_KEY = "b98f7be45fc63bf78b8ae02e";

/**
 * VERIFICACIÓN DE SEGURIDAD
 */
async function verifyAdminRole(uid, companyId) {
  if (uid === companyId) return true;

  const userDoc = await admin.firestore()
    .collection('companies')
    .doc(companyId)
    .collection('users')
    .doc(uid)
    .get();

  if (!userDoc.exists) return false; 
  
  const userData = userDoc.data();
  return userData.role === 'admin' && userData.isActive === true;
}

// ==================================================================
// 1. CREAR EMPLEADO
// ==================================================================
exports.createEmployee = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Debes iniciar sesión.');
  }

  const { email, password, name, role, companyId } = request.data;
  const callerUid = request.auth.uid; 

  const isAdmin = await verifyAdminRole(callerUid, companyId);
  if (!isAdmin) {
    throw new HttpsError('permission-denied', 'No tienes permisos de administrador en esta empresa.');
  }

  try {
    const userRecord = await admin.auth().createUser({
      email: email,
      password: password,
      displayName: name,
    });

    const newUserId = userRecord.uid;

    await admin.firestore()
      .collection('companies')
      .doc(companyId) 
      .collection('users')
      .doc(newUserId)
      .set({
        id: newUserId,
        name: name,
        email: email,
        role: role,
        ownerId: companyId, 
        isActive: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });

    await admin.firestore()
      .collection('user_directory')
      .doc(email)
      .set({
        uid: newUserId,
        ownerId: companyId,
        role: role
      });

    return { success: true, message: 'Usuario creado correctamente' };

  } catch (error) {
    console.error("Error creating user:", error);
    if (error.code === 'auth/email-already-exists') {
        throw new HttpsError('already-exists', 'El correo electrónico ya está registrado.');
    }
    throw new HttpsError('internal', error.message);
  }
});

// ==================================================================
// 2. ELIMINAR EMPLEADO
// ==================================================================
exports.deleteEmployee = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Debes iniciar sesión.');
  
  const { uid, companyId } = request.data; 
  const callerUid = request.auth.uid;

  const isAdmin = await verifyAdminRole(callerUid, companyId);
  if (!isAdmin) throw new HttpsError('permission-denied', 'No tienes permisos para eliminar.');

  if (uid === callerUid || uid === companyId) {
    throw new HttpsError('invalid-argument', 'No puedes eliminarte a ti mismo ni al dueño.');
  }

  try {
    await admin.auth().deleteUser(uid);
    
    await admin.firestore()
      .collection('companies').doc(companyId)
      .collection('users').doc(uid).delete();

    return { success: true, message: 'Usuario eliminado' };
  } catch (error) {
    console.error("Error deleting user:", error);
    throw new HttpsError('internal', error.message);
  }
});

// ==================================================================
// 3. CAMBIAR ACCESO (BLOQUEAR/ACTIVAR)
// ==================================================================
exports.toggleEmployeeAccess = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Debes iniciar sesión.');

  const { uid, companyId, isActive } = request.data;
  const callerUid = request.auth.uid;

  const isAdmin = await verifyAdminRole(callerUid, companyId);
  if (!isAdmin) throw new HttpsError('permission-denied', 'No tienes permisos.');

  if (uid === callerUid || uid === companyId) {
    throw new HttpsError('invalid-argument', 'No puedes bloquearte a ti mismo ni al dueño.');
  }

  try {
    await admin.auth().updateUser(uid, { disabled: !isActive });
    
    if (!isActive) {
      await admin.auth().revokeRefreshTokens(uid);
    }

    await admin.firestore()
      .collection('companies').doc(companyId)
      .collection('users').doc(uid).update({ isActive: isActive });

    return { success: true };
  } catch (error) {
    console.error("Error toggling access:", error);
    throw new HttpsError('internal', error.message);
  }
});

// ==================================================================
// 4. EMITIR FACTURA ELECTRÓNICA SEGURA (PLEMSI) - ON CALL
// ==================================================================
exports.emitirFacturaPlemsi = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Debes iniciar sesión.');

    const { companyId, saleId, client, cartItems, paymentMethods, additionalCosts, paymentDeadline } = request.data;

    try {
        const db = admin.firestore();

        const configSnap = await db.collection('companies').doc(companyId).collection('config').doc('fe_config').get();
        if (!configSnap.exists) throw new HttpsError('not-found', "Credenciales de Plemsi no configuradas.");
        const feConfig = configSnap.data();

        const salesSnap = await db.collection('companies').doc(companyId).collection('sales').where('isElectronicInvoice', '==', true).count().get();
        const currentNumber = salesSnap.data().count + 1;

        const mapDocType = (type) => {
            const t = (type || '').toUpperCase();
            if (t === 'CC') return 3; if (t === 'NIT') return 6; if (t === 'TI') return 2;
            if (t === 'CE') return 4; if (t === 'PAS') return 5; return 3;
        };
        const mapPayMethod = (method) => {
            if (method === 'Efectivo') return 10; if (method === 'Transferencia') return 42;
            if (method === 'Tarjeta') return 48; return 10;
        };
        const calculateDV = (docNum) => {
            if (!docNum) return "0";
            const clean = docNum.replace(/[^0-9]/g, '');
            if (!clean) return "0";
            const mults = [3, 7, 13, 17, 19, 23, 29, 37, 41, 43, 47, 53, 59, 67, 71];
            let sum = 0;
            for (let i = 0; i < clean.length; i++) {
                sum += parseInt(clean[clean.length - 1 - i]) * mults[i];
            }
            const mod = sum % 11;
            return mod > 1 ? (11 - mod).toString() : mod.toString();
        };

        let itemsList = [];
        let taxesMap = {};
        let sumLineExtensionAmount = 0.0;
        let sumTaxExclusiveTotal = 0.0;
        let sumTotalTaxes = 0.0;
        let sumTaxInclusiveTotal = 0.0;

        cartItems.forEach(cartItem => {
            const product = cartItem.product;
            const quantity = cartItem.quantity || 1;
            let lineGrossTotalWithTax = (cartItem.price || 0) * quantity;
            let lineDiscountWithTax = 0.0;

            (additionalCosts || []).forEach(cost => {
                if (cost.amount < 0 && (cost.reason || '').includes(`(${product.name})`)) {
                    lineDiscountWithTax += Math.abs(cost.amount);
                }
            });

            let taxDivisor = product.taxRate > 0 ? (1 + (product.taxRate / 100)) : 1.0;
            let originalBase = lineGrossTotalWithTax / taxDivisor;
            let discountBase = lineDiscountWithTax / taxDivisor;
            let adjustedBase = originalBase - discountBase;

            let currentTaxRate = (product.taxType === 'EXCLUIDO' || product.taxType === 'EXENTO') ? 0.0 : (product.taxRate || 0);
            let taxId = product.taxType === 'INC' ? 4 : 1;
            let itemTaxAmount = parseFloat((adjustedBase * (currentTaxRate / 100)).toFixed(2));

            let itemTaxTotals = [{
                tax_id: taxId, percent: currentTaxRate, tax_amount: itemTaxAmount, taxable_amount: parseFloat(adjustedBase.toFixed(2))
            }];

            let taxKey = `${taxId}_${currentTaxRate}`;
            if (!taxesMap[taxKey]) taxesMap[taxKey] = { tax_id: taxId, percent: currentTaxRate, tax_amount: 0.0, taxable_amount: 0.0 };
            
            taxesMap[taxKey].tax_amount += itemTaxAmount;
            taxesMap[taxKey].taxable_amount += adjustedBase;

            let roundedAdjustedBase = parseFloat(adjustedBase.toFixed(2));
            sumTaxExclusiveTotal += roundedAdjustedBase;
            sumTotalTaxes += itemTaxAmount;

            let lineAllowances = [];
            if (discountBase > 0) {
                lineAllowances.push({
                    discount_id: 1, charge_indicator: false, allowance_charge_reason: "Descuento Promocional",
                    base_amount: parseFloat(originalBase.toFixed(2)), amount: parseFloat(discountBase.toFixed(2)),
                    multiplier_factor_numeric: parseFloat(((discountBase / originalBase) * 100).toFixed(2))
                });
            }

            itemsList.push({
                unit_measure_id: 70, line_extension_amount: roundedAdjustedBase, free_of_charge_indicator: false,
                allowance_charges: lineAllowances, tax_totals: itemTaxTotals, description: product.name || 'Producto', notes: "",
                code: (!product.barcode || product.barcode === '') ? (product.id || 'PROD').substring(0,6).toUpperCase() : product.barcode,
                type_item_identification_id: 1, price_amount: parseFloat((originalBase / quantity).toFixed(2)),
                base_quantity: quantity, invoiced_quantity: quantity
            });
        });

        (additionalCosts || []).forEach(cost => {
            if (cost.amount > 0) {
                let roundedAmount = parseFloat(cost.amount.toFixed(2));
                sumTaxExclusiveTotal += roundedAmount;

                let taxKeyExtra = '1_0';
                if (!taxesMap[taxKeyExtra]) taxesMap[taxKeyExtra] = { tax_id: 1, percent: 0, tax_amount: 0, taxable_amount: 0 };
                taxesMap[taxKeyExtra].taxable_amount += roundedAmount;

                itemsList.push({
                    unit_measure_id: 70, line_extension_amount: roundedAmount, free_of_charge_indicator: false, allowance_charges: [],
                    tax_totals: [{ tax_id: 1, percent: 0, tax_amount: 0, taxable_amount: roundedAmount }],
                    description: cost.reason || 'Cargo Extra', notes: "", code: "CARGO_EXTRA",
                    type_item_identification_id: 1, price_amount: roundedAmount, base_quantity: 1, invoiced_quantity: 1
                });
            }
        });

        sumTaxInclusiveTotal = sumTaxExclusiveTotal + sumTotalTaxes;

        let allTaxTotals = Object.values(taxesMap).map(t => ({
            tax_id: t.tax_id, percent: t.percent, tax_amount: parseFloat(t.tax_amount.toFixed(2)), taxable_amount: parseFloat(t.taxable_amount.toFixed(2))
        }));

        const now = new Date();
        const colTime = new Date(now.getTime() - (5 * 60 * 60 * 1000));
        const dateStr = colTime.toISOString().split('T')[0]; 
        const timeStr = colTime.toISOString().split('T')[1].split('.')[0]; 

        const initialPaymentMethod = (paymentMethods && paymentMethods.length > 0) ? paymentMethods[0].method : 'Efectivo';

        let dueDateStr = dateStr;
        if (paymentDeadline) {
            dueDateStr = paymentDeadline.split('T')[0]; 
        }

        const payload = {
            date: dateStr, time: timeStr, prefix: feConfig.prefix, number: currentNumber, orderReference: { id_order: saleId },
            send_email: true,
            customer: {
                identification_number: (client.idNumber || '').replace(/[^0-9]/g, ''), dv: calculateDV(client.idNumber),
                name: client.name || 'Cliente', phone: (client.phone || '').replace(/[^0-9]/g, ''), address: client.address || "No registra",
                email: client.email || '', merchant_registration: "00000000", type_document_identification_id: mapDocType(client.idType),
                type_organization_id: client.personType === '1' ? 1 : 2, type_liability_id: 117,
                municipality_code: client.daneCode || "11001", type_regime_id: client.taxRegime === '48' ? 0 : 1
            },
            payment: {
                payment_form_id: (paymentMethods || []).some(p => p.method === 'Crédito') ? 2 : 1,
                payment_method_id: mapPayMethod(initialPaymentMethod), 
                payment_due_date: dueDateStr, 
                duration_measure: "0"
            },
            generalAllowances: [], items: itemsList, resolution: feConfig.resolutionNumber, allowanceTotal: 0,
            invoiceBaseTotal: parseFloat(sumTaxExclusiveTotal.toFixed(2)), invoiceTaxExclusiveTotal: parseFloat(sumTaxExclusiveTotal.toFixed(2)),
            invoiceTaxInclusiveTotal: parseFloat(sumTaxInclusiveTotal.toFixed(2)), totalToPay: parseFloat(sumTaxInclusiveTotal.toFixed(2)),
            allTaxTotals: allTaxTotals
        };

        const plemsiUrl = feConfig.isTestEnvironment ? "https://pruebas.plemsi.com/api/billing/invoice" : "https://api.plemsi.com/api/billing/invoice";
        
        const response = await axios.post(plemsiUrl, payload, {
            headers: { "Authorization": `Bearer ${PLEMSI_MASTER_API_KEY}`, "Content-Type": "application/json" },
            validateStatus: function (status) {
                return status < 600; 
            }
        });

        if (response.data.success === true) {
            let qrText = response.data.data.QRCode || "";
            let linkInicio = qrText.indexOf("http");
            let enlaceDian = linkInicio !== -1 ? qrText.substring(linkInicio).trim() : "";
            
            let cufeFinal = response.data.data.cude || response.data.data.cufe || '';
            if (enlaceDian === "" && cufeFinal !== "") {
                enlaceDian = feConfig.isTestEnvironment 
                    ? `https://catalogo-vpfe-hab.dian.gov.co/document/searchqr?documentkey=${cufeFinal}`
                    : `https://catalogo-vpfe.dian.gov.co/document/searchqr?documentkey=${cufeFinal}`;
            }

            return { 
                status: 'Aceptada', 
                cufe: cufeFinal, 
                pdfUrl: enlaceDian, 
                prefix: feConfig.prefix,
                number: currentNumber
            };
        } else {
            console.error("Rechazo DIAN:", JSON.stringify(response.data.data));
            return { status: 'Rechazada', error: 'Rechazado por la DIAN' };
        }
    } catch (error) {
        console.error("Error crítico en Plemsi:", error);
        return { status: 'Pendiente', error: 'Fallo de conexión o servidor' };
    }
});

// ==================================================================
// 5. OBTENER PDF DE LA FACTURA (PLEMSI)
// ==================================================================
exports.obtenerPdfPlemsi = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Debes iniciar sesión.');

    const { companyId, prefix, number } = request.data;

    try {
        const db = admin.firestore();
        const configSnap = await db.collection('companies').doc(companyId).collection('config').doc('fe_config').get();
        const feConfig = configSnap.data();

        const plemsiUrl = feConfig.isTestEnvironment 
            ? `https://pruebas.plemsi.com/api/billing/invoice/${prefix}/${number}` 
            : `https://api.plemsi.com/api/billing/invoice/${prefix}/${number}`;
        
        const response = await axios.get(plemsiUrl, {
            headers: { "Authorization": `Bearer ${PLEMSI_MASTER_API_KEY}` }
        });

        if (response.data.success) {
            return { success: true, pdfUrl: response.data.data.pdf_url || response.data.data.pdfUrl };
        } else {
            throw new Error("No se pudo obtener el PDF");
        }
    } catch (error) {
        console.error("Error obteniendo PDF:", error);
        throw new HttpsError('internal', 'Error al conectar con Plemsi para el PDF.');
    }
});

// ==================================================================
// 6. REENVIAR CORREO AL CLIENTE (PLEMSI)
// ==================================================================
exports.reenviarCorreoPlemsi = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Debes iniciar sesión.');

    const { companyId, prefix, number, email } = request.data;

    try {
        const db = admin.firestore();
        const configSnap = await db.collection('companies').doc(companyId).collection('config').doc('fe_config').get();
        const feConfig = configSnap.data();

        const plemsiUrl = feConfig.isTestEnvironment 
            ? "https://pruebas.plemsi.com/api/billing/invoice/send-email" 
            : "https://api.plemsi.com/api/billing/invoice/send-email";
        
        const payload = {
            prefix: prefix,
            number: number,
            email: email
        };

        const response = await axios.post(plemsiUrl, payload, {
            headers: { "Authorization": `Bearer ${PLEMSI_MASTER_API_KEY}`, "Content-Type": "application/json" }
        });

        return { success: response.data.success, message: "Correo enviado con éxito." };
    } catch (error) {
        console.error("Error reenviando correo:", error);
        throw new HttpsError('internal', 'No se pudo reenviar el correo.');
    }
});

// ==================================================================
// 7. EMITIR NOTA CRÉDITO (ANULAR FACTURA)
// ==================================================================
exports.emitirNotaCreditoPlemsi = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Debes iniciar sesión.');

    const { companyId, saleId, originalPrefix, originalNumber, originalCufe, reason } = request.data;

    try {
        const db = admin.firestore();
        const configSnap = await db.collection('companies').doc(companyId).collection('config').doc('fe_config').get();
        const feConfig = configSnap.data();

        // 1. OBTENER LA VENTA ORIGINAL
        const saleSnap = await db.collection('companies').doc(companyId).collection('sales').doc(saleId).get();
        if (!saleSnap.exists) throw new HttpsError('not-found', "La venta original no existe.");
        const saleData = saleSnap.data();

        // 2. OBTENER DATOS DEL CLIENTE (Búsqueda robusta)
        let clientQuery;
        
        if (saleData.clientIdNumber) {
            // A) Ventas nuevas: Búsqueda exacta por número de documento (NIT/CC)
            clientQuery = await db.collection('companies').doc(companyId).collection('clients')
                .where('idNumber', '==', saleData.clientIdNumber).limit(1).get();
        } else {
            // B) Ventas antiguas: Fallback por nombre (Salvavidas)
            clientQuery = await db.collection('companies').doc(companyId).collection('clients')
                .where('name', '==', saleData.clientName).limit(1).get();
        }

        if (clientQuery.empty) throw new HttpsError('not-found', "No se encontraron los datos del cliente para la anulación.");
        const client = clientQuery.docs[0].data();

        // 3. FUNCIONES DE MAPEO (Copiadas de emitirFacturaPlemsi)
        const mapDocType = (type) => {
            const t = (type || '').toUpperCase();
            if (t === 'CC') return 3; if (t === 'NIT') return 6; if (t === 'TI') return 2;
            if (t === 'CE') return 4; if (t === 'PAS') return 5; return 3;
        };
        const calculateDV = (docNum) => {
            if (!docNum) return "0";
            const clean = docNum.replace(/[^0-9]/g, '');
            if (!clean) return "0";
            const mults = [3, 7, 13, 17, 19, 23, 29, 37, 41, 43, 47, 53, 59, 67, 71];
            let sum = 0;
            for (let i = 0; i < clean.length; i++) {
                sum += parseInt(clean[clean.length - 1 - i]) * mults[i];
            }
            const mod = sum % 11;
            return mod > 1 ? (11 - mod).toString() : mod.toString();
        };

        // 4. RECONSTRUIR ITEMS Y MATEMÁTICAS TRIBUTARIAS
        let itemsList = [];
        let taxesMap = {};
        let sumTaxExclusiveTotal = 0.0;
        let sumTotalTaxes = 0.0;
        let sumTaxInclusiveTotal = 0.0;

        (saleData.items || []).forEach(item => {
            const quantity = item.quantity || 1;
            let lineGrossTotalWithTax = (item.price || 0) * quantity;
            let lineDiscountWithTax = 0.0;

            (saleData.additionalCosts || []).forEach(cost => {
                if (cost.amount < 0 && (cost.reason || '').includes(`(${item.name})`)) {
                    lineDiscountWithTax += Math.abs(cost.amount);
                }
            });

            let taxDivisor = item.taxRate > 0 ? (1 + (item.taxRate / 100)) : 1.0;
            let originalBase = lineGrossTotalWithTax / taxDivisor;
            let discountBase = lineDiscountWithTax / taxDivisor;
            let adjustedBase = originalBase - discountBase;

            let currentTaxRate = (item.taxType === 'EXCLUIDO' || item.taxType === 'EXENTO') ? 0.0 : (item.taxRate || 0);
            let taxId = item.taxType === 'INC' ? 4 : 1;
            let itemTaxAmount = parseFloat((adjustedBase * (currentTaxRate / 100)).toFixed(2));

            let itemTaxTotals = [{
                tax_id: taxId, percent: currentTaxRate, tax_amount: itemTaxAmount, taxable_amount: parseFloat(adjustedBase.toFixed(2))
            }];

            let taxKey = `${taxId}_${currentTaxRate}`;
            if (!taxesMap[taxKey]) taxesMap[taxKey] = { tax_id: taxId, percent: currentTaxRate, tax_amount: 0.0, taxable_amount: 0.0 };
            
            taxesMap[taxKey].tax_amount += itemTaxAmount;
            taxesMap[taxKey].taxable_amount += adjustedBase;

            let roundedAdjustedBase = parseFloat(adjustedBase.toFixed(2));
            sumTaxExclusiveTotal += roundedAdjustedBase;
            sumTotalTaxes += itemTaxAmount;

            let lineAllowances = [];
            if (discountBase > 0) {
                lineAllowances.push({
                    discount_id: 1, charge_indicator: false, allowance_charge_reason: "Descuento Promocional",
                    base_amount: parseFloat(originalBase.toFixed(2)), amount: parseFloat(discountBase.toFixed(2)),
                    multiplier_factor_numeric: parseFloat(((discountBase / originalBase) * 100).toFixed(2))
                });
            }

            itemsList.push({
                unit_measure_id: 70, line_extension_amount: roundedAdjustedBase, free_of_charge_indicator: false,
                allowance_charges: lineAllowances, tax_totals: itemTaxTotals, description: item.name || 'Producto', notes: "",
                code: (!item.productId || item.productId === '') ? 'PROD' : item.productId.substring(0,6).toUpperCase(),
                type_item_identification_id: 1, price_amount: parseFloat((originalBase / quantity).toFixed(2)),
                base_quantity: quantity, invoiced_quantity: quantity
            });
        });

        // 5. RECONSTRUIR CARGOS EXTRAS POSITIVOS
        (saleData.additionalCosts || []).forEach(cost => {
            if (cost.amount > 0) {
                let roundedAmount = parseFloat(cost.amount.toFixed(2));
                sumTaxExclusiveTotal += roundedAmount;

                let taxKeyExtra = '1_0';
                if (!taxesMap[taxKeyExtra]) taxesMap[taxKeyExtra] = { tax_id: 1, percent: 0, tax_amount: 0, taxable_amount: 0 };
                taxesMap[taxKeyExtra].taxable_amount += roundedAmount;

                itemsList.push({
                    unit_measure_id: 70, line_extension_amount: roundedAmount, free_of_charge_indicator: false, allowance_charges: [],
                    tax_totals: [{ tax_id: 1, percent: 0, tax_amount: 0, taxable_amount: roundedAmount }],
                    description: cost.reason || 'Cargo Extra', notes: "", code: "CARGO_EXTRA",
                    type_item_identification_id: 1, price_amount: roundedAmount, base_quantity: 1, invoiced_quantity: 1
                });
            }
        });

        const ncSnap = await db.collection('companies').doc(companyId).collection('credit_notes').count().get();
        const currentNcNumber = ncSnap.data().count + 1;

        const now = new Date();
        const colTime = new Date(now.getTime() - (5 * 60 * 60 * 1000));
        const dateStr = colTime.toISOString().split('T')[0];
        const timeStr = colTime.toISOString().split('T')[1].split('.')[0];

        // 6. CONSTRUIR PAYLOAD FINAL
        const payload = {
            date: dateStr,
            time: timeStr,
            prefix: "NC", 
            number: currentNcNumber,
            billing_reference: {
                number: originalPrefix + originalNumber,
                uuid: originalCufe,
                issue_date: dateStr 
            },
            discrepancy_response: {
                reference: originalPrefix + originalNumber,
                correction_concept_id: 2, 
                description: reason || "Anulación por devolución del cliente"
            },
            customer: {
                identification_number: (client.idNumber || '').replace(/[^0-9]/g, ''), dv: calculateDV(client.idNumber),
                name: client.name || 'Cliente', phone: (client.phone || '').replace(/[^0-9]/g, ''), address: client.address || "No registra",
                email: client.email || '', merchant_registration: "00000000", type_document_identification_id: mapDocType(client.idType),
                type_organization_id: client.personType === '1' ? 1 : 2, type_liability_id: 117,
                municipality_code: client.daneCode || "11001", type_regime_id: client.taxRegime === '48' ? 0 : 1
            },
            items: itemsList,
            resolution: feConfig.resolutionNumber 
        };

        const plemsiUrl = feConfig.isTestEnvironment 
            ? "https://pruebas.plemsi.com/api/billing/credit-note" 
            : "https://api.plemsi.com/api/billing/credit-note";

        const response = await axios.post(plemsiUrl, payload, {
            headers: { "Authorization": `Bearer ${PLEMSI_MASTER_API_KEY}`, "Content-Type": "application/json" },
            validateStatus: status => status < 600
        });

        if (response.data.success) {
            await db.collection('companies').doc(companyId).collection('credit_notes').add({
                ncPrefix: "NC",
                ncNumber: currentNcNumber,
                originalFactura: originalPrefix + originalNumber,
                cude: response.data.data.cude,
                date: admin.firestore.FieldValue.serverTimestamp()
            });
            return { status: 'Aceptada', cude: response.data.data.cude };
        } else {
            console.error("Rechazo DIAN (Nota Crédito):", JSON.stringify(response.data.data));
            return { status: 'Rechazada', error: 'Rechazado por la DIAN' };
        }
    } catch (error) {
        console.error("Error crítico emitiendo Nota Crédito:", error);
        throw new HttpsError('internal', 'Fallo conectando al servidor.');
    }
});

// ==================================================================
// 8. WEBHOOK DE WOMPI (RECEPCIÓN DE PAGOS Y RENOVACIÓN AUTOMÁTICA)
// ==================================================================
exports.wompiTransactionWebhook = onRequest(async (req, res) => {
    try {
        const payload = req.body;

        if (payload && payload.event === 'transaction.updated') {
            const transaction = payload.data.transaction;
            const signature = payload.signature; 
            const timestamp = payload.timestamp; 

            // 1. SEGURIDAD: Usamos tu secreto de eventos para validar la firma
            const eventosSecret = "test_events_8e0AJmuk2WlSfgFbHqn9qLyKNDlkjbEH";
            const concatenatedString = `${transaction.id}${transaction.status}${transaction.amount_in_cents}${timestamp}${eventosSecret}`;
            const hash = crypto.createHash('sha256').update(concatenatedString).digest('hex');

            if (hash !== signature.checksum) {
                console.error("❌ ALERTA: Firma de Wompi inválida.");
                return res.status(403).send("Invalid signature");
            }

            // 2. PROCESAR SI FUE APROBADO
            if (transaction.status === 'APPROVED') {
                const reference = transaction.reference; 
                const parts = reference.split('_');
                
                if (parts.length >= 2) {
                    const rawPlanId = parts[0]; 
                    const companyId = parts[1];
                    const db = admin.firestore();
                    
                    // ========================================================
                    // NUEVO: ESCENARIO A (COMPRA DE PAQUETE DE FACTURAS)
                    // ========================================================
                    if (rawPlanId.startsWith('PKG-')) {
                        const amountToAdd = parseInt(rawPlanId.split('-')[1]); 
                        const feConfigRef = db.collection('companies').doc(companyId).collection('config').doc('fe_config');
                        
                        await db.runTransaction(async (t) => {
                            const feSnap = await t.get(feConfigRef);
                            let currentExtra = 0;
                            if (feSnap.exists && feSnap.data().extraBalance) {
                                currentExtra = feSnap.data().extraBalance;
                            }
                            
                            t.set(feConfigRef, {
                                extraBalance: currentExtra + amountToAdd,
                                updatedAt: admin.firestore.FieldValue.serverTimestamp()
                            }, { merge: true });
                        });
                        
                        console.log(`✅ PAQUETE COMPRADO: Empresa ${companyId} | +${amountToAdd} facturas prepago.`);
                    } 
                    // ========================================================
                    // TU CÓDIGO INTACTO: ESCENARIO B (SUSCRIPCIONES)
                    // ========================================================
                    else {
                        const isEmpresarial = rawPlanId.includes('EMPRESARIAL');
                        const isAnual = rawPlanId.includes('ANUAL');
                        
                        const finalPlanStatus = isEmpresarial ? 'empresarial' : 'pro';
                        const daysToAdd = isAnual ? 365 : 30; 
                        
                        const profileRef = db.collection('companies').doc(companyId).collection('config').doc('profile');
                        
                        await db.runTransaction(async (t) => {
                            const profileSnap = await t.get(profileRef);
                            if (!profileSnap.exists) return;
                            
                            const profileData = profileSnap.data();
                            const now = new Date();
                            let currentEndDate = profileData.trialEndsAt ? profileData.trialEndsAt.toDate() : now;
                            
                            if (currentEndDate < now) {
                                currentEndDate = now;
                            }
                            
                            const newEndDate = new Date(currentEndDate);
                            newEndDate.setDate(newEndDate.getDate() + daysToAdd);
                            
                            t.update(profileRef, {
                                subscriptionStatus: finalPlanStatus,
                                trialEndsAt: admin.firestore.Timestamp.fromDate(newEndDate)
                            });
                        });
                        
                        console.log(`✅ Pago Exitoso: Empresa ${companyId} | Plan: ${finalPlanStatus} | Días sumados: ${daysToAdd}`);
                    }
                }
            }
        }
        res.status(200).send("Webhook procesado");
    } catch (error) {
        console.error("❌ Error en Webhook:", error);
        res.status(500).send("Internal Server Error");
    }
});