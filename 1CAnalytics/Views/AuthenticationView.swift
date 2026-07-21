import SwiftUI

struct AuthenticationView: View {
    @ObservedObject var viewModel: AuthenticationViewModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 104, height: 104)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 26))
                .shadow(color: Color.accentColor.opacity(0.25), radius: 24, y: 12)

            VStack(spacing: 10) {
                Text("Аналитика РУДН")
                    .font(.largeTitle.bold())

                Text("Войдите с помощью RUDN ID, чтобы открыть управленческие показатели.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(spacing: 12) {
                Button {
                    Task { await viewModel.signIn() }
                } label: {
                    HStack(spacing: 10) {
                        if case .signingIn = viewModel.state {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                        }

                        Text("Войти через RUDN ID")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: 360)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .disabled(viewModel.state == .signingIn)

                if case let .failed(message) = viewModel.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
            }

            Spacer()

            Text("Для входа откроется защищённая страница id.rudn.ru")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground())
    }
}
