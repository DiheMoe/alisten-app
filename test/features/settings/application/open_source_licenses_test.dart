import 'package:alisten/features/settings/application/open_source_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

LicenseEntry _license(List<String> packages, String text) =>
    LicenseEntryWithLineBreaks(packages, text);

// 每个包一行：包名及各份许可全文，以“|”分隔。
List<String> _summary(List<PackageLicenses> packages) => [
  for (final package in packages)
    '${package.package}: ${package.licenses.map(_text).join(' | ')}',
];

String _text(LicenseEntry license) =>
    license.paragraphs.map((paragraph) => paragraph.text).join(' ');

void main() {
  test('licenses are grouped by package, packages sorted by name ignoring '
      'case, and a license naming several packages is listed under each', () {
    final grouped = groupLicensesByPackage([
      _license(['dio'], 'dio first'),
      _license(['Plus Jakarta Sans'], 'OFL'),
      _license(['skia', 'angle'], 'shared'),
      _license(['dio'], 'dio second'),
    ]);

    expect(_summary(grouped), [
      'angle: shared',
      'dio: dio first | dio second',
      'Plus Jakarta Sans: OFL',
      'skia: shared',
    ]);
  });

  test('the licenses come from the license registry', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 测试绑定初始化时已登记构建产物中的 NOTICES，这里只检查本测试登记的条目。
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    LicenseRegistry.addLicense(
      () => Stream.fromIterable([
        _license(['b'], 'second'),
        _license(['a'], 'first'),
      ]),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(openSourceLicensesProvider, (_, _) {});

    expect(container.read(openSourceLicensesProvider).isLoading, isTrue);
    expect(_summary(await container.read(openSourceLicensesProvider.future)), [
      'a: first',
      'b: second',
    ]);
  });
}
