/// The integer used to represent a currency in it's 'minor units' form.
///
/// e.g. 100 USD will be represented as `100`.
#if swift(<5.8)
#else
@_documentation(visibility: private)
#endif
public typealias CurrencyMinorUnitRepresentation = Int64
