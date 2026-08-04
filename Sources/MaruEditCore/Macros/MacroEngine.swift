import Foundation
import JavaScriptCore

public enum MacroValue: Equatable, Sendable {
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
}

public struct MacroRunResult: Equatable, Sendable {
    public let value: MacroValue
    public let duration: TimeInterval
}

public struct MacroJavaScriptError: Error, Equatable, Sendable {
    public let message: String
    public let stack: String?
    public let line: Int?
    public let column: Int?
}

public enum MacroExecutionError: Error, Equatable, Sendable {
    case cancelled
    case timedOut
    case javascript(MacroJavaScriptError)
}

public final class MacroCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Runs one macro in one fresh JavaScriptCore VM and context.
///
/// No application, document, filesystem, network, or arbitrary Objective-C
/// object is placed in the global namespace. Host capabilities are added as
/// narrow JavaScript functions under the frozen `maru` object.
public final class MacroEngine: @unchecked Sendable {
    public static let apiVersion = 1
    public static let defaultTimeout: TimeInterval = 5

    private let queue: DispatchQueue

    public init(queue: DispatchQueue = DispatchQueue(
        label: "jp.maruedit.macro-engine", qos: .userInitiated)) {
        self.queue = queue
    }

    @discardableResult
    public func run(
        _ source: String,
        timeout: TimeInterval = MacroEngine.defaultTimeout,
        host: MacroHost? = nil,
        completion: @escaping @Sendable (Result<MacroRunResult, MacroExecutionError>) -> Void
    ) -> MacroCancellationToken {
        let token = MacroCancellationToken()
        queue.async { [self] in
            completion(execute(source, timeout: timeout, cancellation: token, host: host))
        }
        return token
    }

    public func execute(
        _ source: String,
        timeout: TimeInterval = MacroEngine.defaultTimeout,
        cancellation: MacroCancellationToken = MacroCancellationToken(),
        host: MacroHost? = nil
    ) -> Result<MacroRunResult, MacroExecutionError> {
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + max(0, timeout)
        guard !cancellation.isCancelled else { return .failure(.cancelled) }
        guard timeout > 0 else { return .failure(.timedOut) }

        // A new virtual machine prevents objects and globals leaking between
        // runs, even when callers invoke execute concurrently.
        let virtualMachine = JSVirtualMachine()
        guard let context = JSContext(virtualMachine: virtualMachine) else {
            return .failure(.javascript(.init(
                message: "Unable to create JavaScript context.",
                stack: nil, line: nil, column: nil)))
        }

        var capturedException: JSValue?
        context.exceptionHandler = { _, exception in capturedException = exception }

        let check: @convention(block) () -> String? = {
            if cancellation.isCancelled { return "cancelled" }
            if ProcessInfo.processInfo.systemUptime >= deadline { return "timedOut" }
            return nil
        }
        let uppercase: @convention(block) (String) -> String = { $0.uppercased() }
        let lowercase: @convention(block) (String) -> String = { $0.lowercased() }
        let trim: @convention(block) (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normalizeLineEndings: @convention(block) (String) -> String = {
            $0.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        }
        context.setObject(check, forKeyedSubscript: "__maruCheck" as NSString)
        context.setObject(uppercase, forKeyedSubscript: "__maruUppercase" as NSString)
        context.setObject(lowercase, forKeyedSubscript: "__maruLowercase" as NSString)
        context.setObject(trim, forKeyedSubscript: "__maruTrim" as NSString)
        context.setObject(normalizeLineEndings,
                          forKeyedSubscript: "__maruNormalizeLineEndings" as NSString)
        install(host: host, in: context)

        context.evaluateScript(Self.bootstrap)
        if let exception = capturedException {
            return .failure(.javascript(Self.describe(exception)))
        }
        capturedException = nil
        var value = context.evaluateScript(source, withSourceURL: URL(string: "maru://macro.js"))
        if capturedException == nil, let promise = value,
           promise.isObject, promise.hasProperty("then") {
            var resolved: JSValue?
            var rejected: JSValue?
            let fulfill: @convention(block) (JSValue) -> Void = { resolved = $0 }
            let reject: @convention(block) (JSValue) -> Void = { rejected = $0 }
            promise.invokeMethod("then", withArguments: [fulfill, reject])
            // JavaScriptCore drains jobs created by the immediately resolved
            // host promise before this no-op evaluation returns.
            context.evaluateScript("void 0")
            if let rejected { capturedException = rejected }
            value = resolved
        }
        let duration = ProcessInfo.processInfo.systemUptime - started

        if let exception = capturedException {
            let name = exception.forProperty("name")?.toString()
            if name == "MaruCancelled" { return .failure(.cancelled) }
            if name == "MaruTimedOut" { return .failure(.timedOut) }
            return .failure(.javascript(Self.describe(exception)))
        }
        if cancellation.isCancelled { return .failure(.cancelled) }
        if ProcessInfo.processInfo.systemUptime >= deadline { return .failure(.timedOut) }
        return .success(MacroRunResult(value: Self.convert(value), duration: duration))
    }

    private func install(host: MacroHost?, in context: JSContext) {
        context.setObject(host != nil, forKeyedSubscript: "__maruHasHost" as NSString)
        guard let host else { return }
        let runCommand: @convention(block) (String) -> Bool = host.runCommand
        let documentText: @convention(block) () -> String = host.documentText
        let setDocumentText: @convention(block) (String) -> Void = host.setDocumentText
        let selectionsJSON: @convention(block) () -> String = host.selectionsJSON
        let setSelectionsJSON: @convention(block) (String) -> Bool = host.setSelectionsJSON
        let replaceSelections: @convention(block) (String) -> Void = host.replaceSelections
        let readClipboard: @convention(block) () -> String = host.readClipboard
        let writeClipboard: @convention(block) (String) -> Void = host.writeClipboard
        let showMessage: @convention(block) (String) -> Void = host.showMessage
        let prompt: @convention(block) (String, String) -> String? = host.prompt
        let beginUndo: @convention(block) (String) -> Void = host.beginUndoGroup
        let endUndo: @convention(block) () -> Void = host.endUndoGroup
        let entries: [(String, Any)] = [
            ("__maruRunCommand", runCommand), ("__maruDocumentText", documentText),
            ("__maruSetDocumentText", setDocumentText), ("__maruSelectionsJSON", selectionsJSON),
            ("__maruSetSelectionsJSON", setSelectionsJSON),
            ("__maruReplaceSelections", replaceSelections), ("__maruReadClipboard", readClipboard),
            ("__maruWriteClipboard", writeClipboard), ("__maruShowMessage", showMessage),
            ("__maruPrompt", prompt), ("__maruBeginUndo", beginUndo), ("__maruEndUndo", endUndo)
        ]
        for (name, value) in entries {
            context.setObject(value, forKeyedSubscript: name as NSString)
        }
    }

    private static let bootstrap = #"""
    (() => {
      'use strict';
      const nativeCheck = __maruCheck;
      const nativeUppercase = __maruUppercase;
      const nativeLowercase = __maruLowercase;
      const nativeTrim = __maruTrim;
      const nativeNormalizeLineEndings = __maruNormalizeLineEndings;
      const hasHost = __maruHasHost;
      const check = () => {
        const state = nativeCheck();
        if (state === 'cancelled') {
          const error = new Error('Macro cancelled'); error.name = 'MaruCancelled'; throw error;
        }
        if (state === 'timedOut') {
          const error = new Error('Macro timed out'); error.name = 'MaruTimedOut'; throw error;
        }
      };
      const textCall = (nativeFunction) => (value) => {
        check();
        if (typeof value !== 'string') throw new TypeError('Expected a string');
        const result = nativeFunction(value);
        check();
        return result;
      };
      const text = Object.freeze({
        uppercase: textCall(nativeUppercase),
        lowercase: textCall(nativeLowercase),
        trim: textCall(nativeTrim),
        normalizeLineEndings: textCall(nativeNormalizeLineEndings)
      });
      const api = { apiVersion: 1, checkCancellation: check, text };
      if (hasHost) {
        const native = {
          runCommand: __maruRunCommand, documentText: __maruDocumentText,
          setDocumentText: __maruSetDocumentText, selectionsJSON: __maruSelectionsJSON,
          setSelectionsJSON: __maruSetSelectionsJSON, replaceSelections: __maruReplaceSelections,
          readClipboard: __maruReadClipboard, writeClipboard: __maruWriteClipboard,
          showMessage: __maruShowMessage, prompt: __maruPrompt,
          beginUndo: __maruBeginUndo, endUndo: __maruEndUndo
        };
        api.commands = Object.freeze({ run: (id) => {
          check();
          if (typeof id !== 'string') return Promise.reject(new TypeError('Expected a command ID'));
          return Promise.resolve(native.runCommand(id));
        }});
        api.document = Object.freeze({
          getText: () => { check(); return native.documentText(); },
          setText: (value) => { check(); if (typeof value !== 'string') throw new TypeError('Expected a string'); native.setDocumentText(value); check(); }
        });
        api.editor = Object.freeze({
          getSelections: () => { check(); return JSON.parse(native.selectionsJSON()); },
          setSelections: (ranges) => { check(); return native.setSelectionsJSON(JSON.stringify(ranges)); },
          replaceSelections: (value) => { check(); if (typeof value !== 'string') throw new TypeError('Expected a string'); native.replaceSelections(value); check(); }
        });
        api.clipboard = Object.freeze({
          readText: () => { check(); return native.readClipboard(); },
          writeText: (value) => { check(); if (typeof value !== 'string') throw new TypeError('Expected a string'); native.writeClipboard(value); }
        });
        api.ui = Object.freeze({
          message: (value) => { check(); native.showMessage(String(value)); },
          prompt: (message, initial = '') => { check(); return native.prompt(String(message), String(initial)); }
        });
        api.undo = Object.freeze({ group: (name, action) => {
          if (typeof action !== 'function') throw new TypeError('Expected a function');
          native.beginUndo(String(name));
          try { return action(); } finally { native.endUndo(); }
        }});
      }
      Object.defineProperty(globalThis, 'maru', {
        value: Object.freeze(api),
        writable: false, configurable: false, enumerable: true
      });
      delete globalThis.__maruCheck;
      delete globalThis.__maruUppercase;
      delete globalThis.__maruLowercase;
      delete globalThis.__maruTrim;
      delete globalThis.__maruNormalizeLineEndings;
      delete globalThis.__maruHasHost;
      for (const name of ['__maruRunCommand','__maruDocumentText','__maruSetDocumentText',
        '__maruSelectionsJSON','__maruSetSelectionsJSON','__maruReplaceSelections',
        '__maruReadClipboard','__maruWriteClipboard','__maruShowMessage','__maruPrompt',
        '__maruBeginUndo','__maruEndUndo']) delete globalThis[name];
    })();
    """#

    private static func describe(_ exception: JSValue) -> MacroJavaScriptError {
        let lineValue = exception.forProperty("line")
        let columnValue = exception.forProperty("column")
        return MacroJavaScriptError(
            message: exception.forProperty("message")?.toString()
                ?? exception.toString() ?? "Unknown JavaScript error",
            stack: exception.forProperty("stack")?.toString(),
            line: lineValue?.isNumber == true ? Int(lineValue!.toInt32()) : nil,
            column: columnValue?.isNumber == true ? Int(columnValue!.toInt32()) : nil)
    }

    private static func convert(_ value: JSValue?) -> MacroValue {
        guard let value, !value.isUndefined, !value.isNull else { return .null }
        if value.isBoolean { return .boolean(value.toBool()) }
        if value.isNumber { return .number(value.toDouble()) }
        return .string(value.toString() ?? "")
    }
}
