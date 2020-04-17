//
//  Dynamic
//  Created by Mhd Hejazi on 4/15/20.
//  Copyright © 2020 Samabox. All rights reserved.
//

import Foundation

class Invocation: Loggable {
    public static var loggingEnabled: Bool = false
    var loggingEnabled: Bool { Self.loggingEnabled }

    private let target: NSObject
    private let selector: Selector

    var invocation: NSObject?

    var numberOfArguments: Int = 0
    var returnLength: Int = 0
    var returnType: UnsafePointer<CChar>?
    var returnTypeString: String? {
        guard let returnType = returnType else { return nil }
        return String(cString: returnType)
    }
    var returnsObject: Bool {
        /// `@` is the type encoding for an object
        returnTypeString == "@"
    }
    var returnsAny: Bool {
        /// `v` is the type encoding for Void
        returnTypeString != "v"
    }
    private(set) var isInvoked: Bool = false

    init(target: NSObject, selector: Selector) throws {
        self.target = target
        self.selector = selector

        log(.start)
        log("# Invocation")
        log("[\(type(of: target)) \(selector)]")
        log("Target:", target)
        log("Selector:", selector)

        try initialize()
    }

    private func initialize() throws {
        /// `NSMethodSignature *methodSignature = [target methodSignatureForSelector: selector]`
        let methodSignature: NSObject
        do {
            let selector = NSSelectorFromString("methodSignatureForSelector:")
            let signature = (@convention(c)(NSObject, Selector, Selector) -> Any).self
            let method = unsafeBitCast(target.method(for: selector), to: signature)
            guard let result = method(target, selector, self.selector) as? NSObject else {
                let error = InvocationError.doesNotRecognizeSelector(type(of: target), self.selector)
                log("ERROR:", error)
                throw error
            }
            methodSignature = result
        }

        /// `numberOfArguments = methodSignature.numberOfArguments`
        self.numberOfArguments = methodSignature.value(forKeyPath: "numberOfArguments") as? Int ?? 0
        log("NumberOfArguments:", numberOfArguments)

        /// `methodReturnLength = methodSignature.methodReturnLength`
        self.returnLength = methodSignature.value(forKeyPath: "methodReturnLength") as? Int ?? 0
        log("ReturnLength:", returnLength)

        /// `methodReturnType = methodSignature.methodReturnType`
        let methodReturnType: UnsafePointer<CChar>
        do {
            let selector = NSSelectorFromString("methodReturnType")
            let signature = (@convention(c)(NSObject, Selector) -> UnsafePointer<CChar>).self
            let method = unsafeBitCast(methodSignature.method(for: selector), to: signature)
            methodReturnType = method(methodSignature, selector)
        }
        self.returnType = methodReturnType
        log("ReturnType:", self.returnTypeString ?? "?")

        /// `NSInvocation *invocation = [NSInvocation invocationWithMethodSignature: methodSignature]`
        let invocation: NSObject
        do {
            let NSInvocation = NSClassFromString("NSInvocation") as AnyObject
            let selector = NSSelectorFromString("invocationWithMethodSignature:")
            let signature = (@convention(c)(AnyObject, Selector, AnyObject) -> AnyObject).self
            let method = unsafeBitCast(NSInvocation.method(for: selector), to: signature)
            guard let result = method(NSInvocation, selector, methodSignature) as? NSObject else {
                let error = InvocationError.doesNotRecognizeSelector(type(of: target), self.selector)
                log("ERROR:", error)
                throw error
            }
            invocation = result
        }
        self.invocation = invocation

        /// `invocation.selector = selector`
        do {
            let selector = NSSelectorFromString("setSelector:")
            let signature = (@convention(c)(NSObject, Selector, Selector) -> Void).self
            let method = unsafeBitCast(invocation.method(for: selector), to: signature)
            method(invocation, selector, self.selector)
        }
    }

    func setArgument(_ argument: Any?, at index: NSInteger) {
        guard let invocation = invocation else { return }

        log("Argument #\(index - 1):", argument ?? "<nil>")

        /// `[invocation setArgument:&argument atIndex:i + 2]`
        let selector = NSSelectorFromString("setArgument:atIndex:")
        let signature = (@convention(c)(NSObject, Selector, UnsafeRawPointer, Int) -> Void).self
        let method = unsafeBitCast(invocation.method(for: selector), to: signature)
        withUnsafePointer(to: argument) { pointer in
            method(invocation, selector, pointer, index)
        }
    }

    func invoke() {
        guard let invocation = invocation, !isInvoked else { return }

        log("Invoking...")

        isInvoked = true

        /// `[invocation invokeWithTarget: target]`
        do {
            let selector = NSSelectorFromString("invokeWithTarget:")
            let signature = (@convention(c)(NSObject, Selector, AnyObject) -> Void).self
            let method = unsafeBitCast(invocation.method(for: selector), to: signature)
            method(invocation, selector, target)
        }

        log(.end)
    }

    func getReturnValue<T>(result: inout T) {
        guard let invocation = invocation else { return }

        /// `[invocation getReturnValue: returnValue]`
        do {
            let selector = NSSelectorFromString("getReturnValue:")
            let signature = (@convention(c)(NSObject, Selector, UnsafeMutableRawPointer) -> Void).self
            let method = unsafeBitCast(invocation.method(for: selector), to: signature)
            withUnsafeMutablePointer(to: &result) { pointer in
                method(invocation, selector, pointer)
            }
        }

        log("getReturnValue() ->", result)
    }

    func returnedObject() -> AnyObject? {
        guard returnsObject, returnLength > 0 else {
            return nil
        }

        var result: AnyObject?

        getReturnValue(result: &result)

        guard let object = result else {
            return nil
        }

        /// `NSInvocation.getReturnValue()` doesn't give us the ownership of the returned object, but the compiler
        /// tries to release this object anyway. So, we are retaining it to balance with the compiler's release.
        return Unmanaged.passRetained(object).takeUnretainedValue()
    }
}

public enum InvocationError: CustomNSError {
    case doesNotRecognizeSelector(_ classType: AnyClass, _ selector: Selector)

    public static var errorDomain: String { String(describing: Invocation.self) }

    public var errorCode: Int {
        switch self {
        case .doesNotRecognizeSelector:
            return 404
        }
    }

    public var errorUserInfo: [String: Any] {
        var message: String
        switch self {
        case .doesNotRecognizeSelector(let classType, let selector):
            message = "'\(String(describing: classType))' doesn't recognize selector '\(selector)'"
        }
        return [NSLocalizedDescriptionKey: message]
    }
}
