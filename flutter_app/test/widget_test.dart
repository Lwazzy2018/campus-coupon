// Small check that needs no internet (the real app needs Supabase to start).
// Run with:  flutter test
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_coupon/theme.dart';

void main() {
  test('App uses the exact Figma colours', () {
    expect(CC.navy, const Color(0xFF003261));
    expect(CC.field, const Color(0xFFD9D9D9));
    expect(CC.card, const Color(0xFFF3EBEB));
  });
}
