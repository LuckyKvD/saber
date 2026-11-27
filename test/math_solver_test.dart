import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/math/math_solver.dart';

String r(String s) => MathSolver.solve(s).result;

void main() {
  test('Rechnen', () {
    expect(r('(12+8)*3/4'), '15');
    expect(r('3+4='), '7');
    expect(r('3+5-'), '8');
    expect(MathSolver.solve('3+5=').writeText, '8');
    expect(MathSolver.solve('1/4').writeText, '0,25');
    expect(r('12:4'), '3');
    expect(r('5x4'), '20');
    expect(r('2,5*2'), '5');
    expect(r('√9+1'), '4');
    expect(r('1/3'), '1/3 ≈ 0,333333');
  });
  test('Lineare Gleichungen', () {
    expect(r('3x+5=20'), 'x = 5');
    expect(r('2(x+3)=14'), 'x = 4');
    expect(r('x/2=3'), 'x = 6');
    expect(r('3x=7'), 'x = 7/3 ≈ 2,333333');
    expect(r('x+x=2x'), 'Die Gleichung ist immer wahr.');
  });
  test('Quadratische Gleichungen', () {
    expect(r('2x^2-8=0'), 'x = -2 oder x = 2');
    expect(r('x^2-2x-3=0'), 'x = -1 oder x = 3');
    expect(r('x^2+1=0'), 'Keine reelle Lösung');
  });
  test('Fehler', () {
    expect(() => MathSolver.solve('1/0'), throwsA(isA<MathError>()));
    expect(() => MathSolver.solve('x+y=3'), throwsA(isA<MathError>()));
  });
}
