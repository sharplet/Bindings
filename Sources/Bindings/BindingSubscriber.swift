import Combine

infix operator <~: DefaultPrecedence

public protocol BindingSubscriber: Subscriber, Cancellable {
  @discardableResult
  static func <~ (subscriber: Self, source: any Publisher<Input, Failure>) -> AnyCancellable
}

extension Publisher {
  @discardableResult
  public static func ~> <B: BindingSubscriber> (source: Self, subscriber: B) -> AnyCancellable
    where Output == B.Input, Failure == B.Failure
  {
    subscriber <~ source
  }
}

// MARK: Optional

extension BindingSubscriber {
  @discardableResult
  public static func <~ <P: Publisher> (subscriber: Self, source: P) -> AnyCancellable
    where Input == P.Output?, Failure == P.Failure
  {
    subscriber <~ source.map(Optional.some)
  }
}

extension Publisher {
  @discardableResult
  public static func ~> <B: BindingSubscriber> (source: Self, subscriber: B) -> AnyCancellable
    where B.Input == Output?, B.Failure == Failure
  {
    subscriber <~ source
  }
}
