import Foundation

enum AppServerRuntimePolicy {
    static let storeConfigOverrides = [
        "cli_auth_credentials_store=\"keyring\"",
        "features.secret_auth_storage=false",
        "features.plugins=false",
        "analytics.enabled=false",
        "otel.exporter=\"none\"",
        "otel.trace_exporter=\"none\"",
        "otel.metrics_exporter=\"none\"",
    ]

    static var storeArguments: [String] {
        storeConfigOverrides.flatMap { ["--config", $0] } + ["--listen", "stdio://"]
    }
}
