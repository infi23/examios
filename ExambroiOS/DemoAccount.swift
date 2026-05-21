import Foundation

/// Deteksi akun demo — untuk keperluan App Review Apple & testing internal.
///
/// Akun demo (mis. "user-demo1") dilonggarkan: Guided Access tidak wajib dan
/// deteksi internet tidak memblokir login. Tujuannya agar reviewer Apple bisa
/// menguji aplikasi dari perangkat ber-internet tanpa harus setup Guided Access.
///
/// Akun siswa reguler tetap menjalani lockdown penuh (Guided Access wajib,
/// internet bebas diblokir). Pelonggaran HANYA berlaku untuk akun ber-prefix
/// "user-demo" — proktor mudah mengenali akun ini di dashboard.
enum DemoAccount {
    /// Prefix Student ID yang dianggap akun demo (case-insensitive).
    private static let prefix = "user-demo"

    static func isDemo(_ studentId: String) -> Bool {
        studentId
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .hasPrefix(prefix)
    }
}
