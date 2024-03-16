import Combine
import os.lock

@available(iOS 9999, macOS 9999, *)
extension AsyncSequence {
  public var publisher: some Publisher<Element, Failure> {
    AsyncSequencePublisher(sequence: self)
  }
}

@available(iOS 9999, macOS 9999, *)
struct AsyncSequencePublisher<Base: AsyncSequence>: Combine.Publisher {
  typealias Output = Base.Element
  typealias Failure = Base.Failure

  var sequence: Base

  func receive(subscriber: some Subscriber<Output, Failure>) {
    let subscription = Subscription(sequence: sequence, downstream: subscriber)
    subscriber.receive(subscription: subscription)
  }
}

@available(iOS 9999, macOS 9999, *)
extension AsyncSequencePublisher {
  final class Subscription<S: Subscriber<Output, Failure>>: Combine.Subscription {
    private struct State {
      var continuation: UnsafeContinuation<Void, Never>?
      var demand: Subscribers.Demand = .none
      var isStarted: Bool = false
      var task: Task<Void, Never>?

      mutating func finish() {
        self = State(isStarted: true)
      }
    }

    private let downstream: S
    private let sequence: Base
    private let state: OSAllocatedUnfairLock<State>

    init(sequence: Base, downstream: S) {
      self.downstream = downstream
      self.sequence = sequence
      state = OSAllocatedUnfairLock(initialState: State())
    }

    func request(_ demand: Subscribers.Demand) {
      let continuation = state.withLock { (state) -> UnsafeContinuation<Void, Never>? in
        state.demand += demand

        if state.isStarted {
          if state.demand > 1, let continuation = state.continuation {
            state.demand -= 1
            return continuation
          }
        } else {
          if state.demand > 1 {
            state.demand -= 1
          }

          state.isStarted = true
          state.task = Task {
            await run()
          }
        }

        return nil
      }

      continuation?.resume()
    }

    func cancel() {
      let (task, continuation) = state.withLock { state in
        defer { state.finish() }
        return (state.task, state.continuation)
      }

      task?.cancel()
      continuation?.resume()
    }

    private func run() async {
      do {
        for try await element in sequence {
          try Task.checkCancellation()
          let additionalDemand = downstream.receive(element)
          await waitForDemand(adding: additionalDemand)
        }
        try Task.checkCancellation()
        state.withLock { $0.finish() }
        downstream.receive(completion: .finished)
      } catch let error as Failure {
        state.withLock { $0.finish() }
        downstream.receive(completion: .failure(error))
      } catch {
        // cancelled
      }
    }

    private func waitForDemand(adding additionalDemand: Subscribers.Demand) async {
      let hasPendingDemand = state.withLock { state in
        state.demand += additionalDemand
        if state.demand > 0 {
          state.demand -= 1
          return true
        } else {
          return false
        }
      }

      if !hasPendingDemand {
        await withUnsafeContinuation { continuation in
          let resumeImmediately = state.withLock { state in
            if state.demand > 0 {
              state.demand -= 1
              return true
            } else {
              state.continuation = continuation
              return false
            }
          }

          if resumeImmediately {
            continuation.resume()
          }
        }
      }
    }
  }
}

@available(iOS 9999, macOS 9999, *)
extension AsyncSequencePublisher: Sendable where Base: Sendable {}

@available(iOS 9999, macOS 9999, *)
extension AsyncSequencePublisher.Subscription: Sendable where Base: Sendable, S: Sendable {}
