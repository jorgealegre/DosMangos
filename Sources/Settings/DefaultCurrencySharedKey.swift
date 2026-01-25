import Sharing

extension SharedKey where Self == AppStorageKey<String>.Default {
    static var defaultCurrency: Self {
        Self[.appStorage("default_currency"), default: "USD"]
    }
}
