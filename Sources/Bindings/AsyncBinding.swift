import Combine
import os.lock

@available(iOS 16.0, *)
public final class AsyncBinding<Owner: BindingOwner, Input: Sendable>: Sendable {
  nonisolated(unsafe) private weak var owner: Owner?
  nonisolated(unsafe) private var task: Task<Void, Never>!

  nonisolated(unsafe) private let receiveValue: (Owner, Input) -> Void
  private let streamContinuation: AsyncStream<Input>.Continuation
  private let subscription: OSAllocatedUnfairLock<(any Subscription)?>

  public init(owner: Owner, isolation: isolated (any Actor)? = #isolation, receiveValue: @escaping (Owner, Input) -> Void) {
    self.owner = owner
    self.receiveValue = receiveValue
    self.subscription = OSAllocatedUnfairLock(uncheckedState: nil)

    let (stream, continuation) = AsyncStream.makeStream(of: Input.self)
    self.streamContinuation = continuation

    self.task = Task { [unowned self] in
      for await input in stream {
        guard let owner = self.owner else {
          cancel()
          return
        }

        isolation?.preconditionIsolated()
        handleInput(input, owner: owner, isolation: isolation)
      }
    }
  }

  private func handleInput(_ input: Input, owner: Owner, isolation: isolated (any Actor)?) {
    receiveValue(owner, input)
  }
}

@available(iOS 16.0, *)
extension AsyncBinding: Subscriber {
  public func receive(subscription: any Subscription) {
    self.subscription.withLock { $0 = subscription }
    subscription.request(.unlimited)
  }

  public func receive(_ input: Input) -> Subscribers.Demand {
    streamContinuation.yield(input)
    return .max(1)
  }

  public func receive(completion: Subscribers.Completion<Never>) {
    streamContinuation.finish()
  }
}

@available(iOS 16.0, *)
extension AsyncBinding: Cancellable {
  public func cancel() {
    subscription.withLock { subscription in
      defer { subscription = nil }
      return subscription
    }?.cancel()
  }
}

@available(iOS 16.0, *)
extension AsyncBinding: BindingSubscriber {
  @discardableResult
  public static func <~ (binding: AsyncBinding, publisher: any Publisher<Input, Failure>) -> AnyCancellable {
    guard let owner = binding.owner else { return AnyCancellable({}) }
    let cancellable = AnyCancellable(binding)
    owner.store(cancellable)
    publisher.subscribe(binding)
    return cancellable
  }
}

// MARK: Swift Concurrency

@available(iOS 9999, macOS 9999, *)
extension AsyncBinding {
  @discardableResult
  public static func <~ (subscriber: AsyncBinding, source: some AsyncSequence<Input, Failure>) -> AnyCancellable {
    subscriber <~ source.publisher
  }

  @discardableResult
  public static func <~ <S: AsyncSequence>(subscriber: AsyncBinding, source: S) -> AnyCancellable
    where Input == S.Element?, Failure == S.Failure
  {
    subscriber <~ source.publisher
  }
}

@available(iOS 9999, macOS 9999, *)
extension AsyncBinding where Input == any Error {
  @discardableResult
  public static func <~ <S: AsyncSequence>(subscriber: AsyncBinding, source: S) -> AnyCancellable
    where S.Element: Error, S.Failure == Failure
  {
    subscriber <~ source.publisher.map { $0 }
  }
}
