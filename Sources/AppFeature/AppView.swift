import SwiftUI

public struct AppView: View {

    @State private var transactions = ["Subscription", "Internet"]
    @State private var isAddViewPresented = false

    public init() {}
    
    public var body: some View {
        NavigationStack {

            ZStack(alignment: .bottom) {
                VStack {
                    Divider()
                    HStack {
                        Spacer()
                        HStack {
                            Text("Income")
                            Text("$0")
                        }
                        Spacer()
                        HStack {
                            Text("Expensas")
                            Text("$0")
                        }

                        Spacer()
                        HStack {
                            Text("Balance")
                            Text("$0")
                        }
                        Spacer()
                    }
                    Divider()

                    Text("October")
                        .font(.largeTitle.bold().lowercaseSmallCaps())

                    List {
                        ForEach(transactions, id: \.self) { transaction in
                            Text(transaction)
                        }
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)

                }

                Button {
                    isAddViewPresented = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(.purple.gradient)

                        Image(systemName: "plus.square")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                    }
                    .frame(width: 80, height: 80)
                }
            }
            .navigationTitle("Overview")
            .sheet(isPresented: $isAddViewPresented) {
                VStack {
                    Text("Add Transaction")
                    Spacer()
                }
                .padding()
            }

        }
    }
}

struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView()
    }
}
