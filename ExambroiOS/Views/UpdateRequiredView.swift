import SwiftUI
import UIKit

/// Layar wajib-update yang ditampilkan secara `fullScreenCover` saat server
/// mengembalikan HTTP 426 untuk endpoint `/api/v1/app/version-check`.
///
/// Hard-block: tidak ada tombol "Lewati". Satu-satunya jalan keluar adalah
/// dengan update via App Store (tombol di bawah).
///
/// `AppStoreID` dibaca dari `Info.plist` (`AppStoreID` key) yang di-injeksi
/// build setting `APP_STORE_ID` dari `project.yml`. Selama nilainya masih
/// placeholder `"0000000000"` (atau kosong), tombol akan disabled untuk
/// mencegah user mendarat di link App Store yang rusak.
struct UpdateRequiredView: View {
    let message: String

    private var appStoreID: String {
        let raw = Bundle.main.infoDictionary?["AppStoreID"] as? String ?? ""
        return raw.trimmingCharacters(in: .whitespaces)
    }

    private var isAppStoreIDValid: Bool {
        !appStoreID.isEmpty && appStoreID != "0000000000"
    }

    var body: some View {
        ZStack {
            Color(hex: "#0f172a").ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 70))
                    .foregroundColor(Color(hex: "#fbbf24"))

                Text("Pembaruan Diperlukan")
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(Color(hex: "#94a3b8"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: openAppStore) {
                    Text("Perbarui Sekarang")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isAppStoreIDValid ? Color(hex: "#fbbf24") : Color(hex: "#475569"))
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .disabled(!isAppStoreIDValid)

                if !isAppStoreIDValid {
                    Text("App Store ID belum dikonfigurasi.\nHubungi administrator.")
                        .font(.caption)
                        .foregroundColor(Color(hex: "#94a3b8"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }

    private func openAppStore() {
        guard isAppStoreIDValid,
              let url = URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)") else { return }
        UIApplication.shared.open(url)
    }
}
