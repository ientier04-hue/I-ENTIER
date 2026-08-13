import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class PatientPharmacyProduct {
  final String id;
  final String pharmacyId;
  final String pharmacyName;
  final String name;
  final String activeIngredient;
  final String category;
  final String strength;
  final String dosageForm;
  final String packSize;
  final bool requiresPrescription;
  final double price;
  final double stockQuantity;

  const PatientPharmacyProduct({
    required this.id,
    required this.pharmacyId,
    required this.pharmacyName,
    required this.name,
    required this.activeIngredient,
    required this.category,
    required this.strength,
    required this.dosageForm,
    required this.packSize,
    required this.requiresPrescription,
    required this.price,
    required this.stockQuantity,
  });

  factory PatientPharmacyProduct.fromRow(Map<String, dynamic> row) {
    String text(String key) => row[key]?.toString().trim() ?? '';
    double number(String key) => row[key] is num
        ? (row[key] as num).toDouble()
        : double.tryParse(text(key)) ?? 0;
    return PatientPharmacyProduct(
      id: text('product_id'),
      pharmacyId: text('pharmacy_id'),
      pharmacyName: text('pharmacy_name'),
      name: text('name'),
      activeIngredient: text('active_ingredient'),
      category: text('category'),
      strength: text('strength'),
      dosageForm: text('dosage_form'),
      packSize: text('pack_size'),
      requiresPrescription: row['requires_prescription'] == true,
      price: number('selling_price'),
      stockQuantity: number('stock_quantity'),
    );
  }
}

class PatientPrescriptionOption {
  final String id;
  final String label;

  const PatientPrescriptionOption({required this.id, required this.label});
}

class PatientPharmacyOrderLine {
  final String productId;
  final int quantity;

  const PatientPharmacyOrderLine({
    required this.productId,
    required this.quantity,
  });

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'quantity': quantity,
  };
}

abstract class PatientPharmacyRepository {
  Stream<List<PatientPharmacyProduct>> watchCatalog();

  Future<List<PatientPrescriptionOption>> listPrescriptions(String patientId);

  Future<String> placeOrder({
    required String pharmacyId,
    required List<PatientPharmacyOrderLine> lines,
    String? prescriptionId,
    String note = '',
  });
}

class SupabasePatientPharmacyRepository implements PatientPharmacyRepository {
  final SupabaseClient client;

  SupabasePatientPharmacyRepository({SupabaseClient? client})
    : client = client ?? Supabase.instance.client;

  @override
  Stream<List<PatientPharmacyProduct>> watchCatalog() async* {
    final refreshes = StreamController<void>();
    void refresh([Object? _]) {
      if (!refreshes.isClosed) refreshes.add(null);
    }

    void fail(Object error, StackTrace stackTrace) {
      if (!refreshes.isClosed) refreshes.addError(error, stackTrace);
    }

    final subscriptions = <StreamSubscription<dynamic>>[
      client
          .schema('ientier')
          .from('pharmacy_products')
          .stream(primaryKey: ['product_id'])
          .listen(refresh, onError: fail),
      client
          .schema('ientier')
          .from('pharmacies')
          .stream(primaryKey: ['pharmacy_id'])
          .listen(refresh, onError: fail),
    ];
    try {
      await for (final _ in refreshes.stream) {
        final rows = await client
            .schema('ientier')
            .from('v_public_pharmacy_products')
            .select()
            .order('name');
        yield rows.map(PatientPharmacyProduct.fromRow).toList(growable: false);
      }
    } finally {
      await Future.wait(
        subscriptions.map((subscription) => subscription.cancel()),
      );
      await refreshes.close();
    }
  }

  @override
  Future<List<PatientPrescriptionOption>> listPrescriptions(
    String patientId,
  ) async {
    final rows = await client
        .schema('ientier')
        .from('prescriptions')
        .select('prescription_id,file_name,doctor_name_snapshot,created_at')
        .eq('patient_id', patientId)
        .eq('status', 'available')
        .order('created_at', ascending: false)
        .limit(50);
    return rows
        .map((row) {
          final doctor = row['doctor_name_snapshot']?.toString().trim() ?? '';
          final file = row['file_name']?.toString().trim() ?? '';
          return PatientPrescriptionOption(
            id: row['prescription_id'].toString(),
            label: doctor.isNotEmpty
                ? 'Ordonnance de $doctor'
                : file.isNotEmpty
                ? file
                : 'Ordonnance enregistrée',
          );
        })
        .toList(growable: false);
  }

  @override
  Future<String> placeOrder({
    required String pharmacyId,
    required List<PatientPharmacyOrderLine> lines,
    String? prescriptionId,
    String note = '',
  }) async {
    final result = await client
        .schema('ientier')
        .rpc(
          'place_pharmacy_order',
          params: {
            'p_pharmacy_id': pharmacyId,
            'p_items': lines
                .map((line) => line.toJson())
                .toList(growable: false),
            'p_prescription_id': prescriptionId,
            'p_customer_name': '',
            'p_customer_phone': '',
            'p_note': note.trim(),
          },
        );
    return result?.toString() ?? '';
  }
}
