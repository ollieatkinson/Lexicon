import SwiftLexicon

let events = Events()

let observer = events.on(where: { event in
	event.matches(I_commerce_ux_type_action.self)
}) { event in
	print(event.description)
}

try events.send(Event(commerce.ui.product.card.buy))
events.finish()
await observer.wait()
observer.cancel()
