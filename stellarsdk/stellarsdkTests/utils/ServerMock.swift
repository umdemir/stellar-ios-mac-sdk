//
//  ServerMock.swift
//  stellarsdkTests
//
//  Created by Rogobete Christian on 06.02.18.
//  Copyright © 2018 Soneso. All rights reserved.
//

import Foundation

class ServerMock: URLProtocol {
    private static var registeredRequestMocks = [RequestMock]()
    
    static func add(mock: RequestMock) {
        registeredRequestMocks.append(mock)
    }
    
    static func remove(mock: RequestMock) {
        if let i = registeredRequestMocks.index(where: { $0 === mock }) {
            registeredRequestMocks.remove(at: i)
        }
    }
    
    static func removeAll() {
        registeredRequestMocks.removeAll()
    }
    
    static func mock(for request: URLRequest) -> RequestMock? {
        return registeredRequestMocks.filter({ $0.canHandle(request: request) }).first
    }
    
    override static func canInit(with request: URLRequest) -> Bool {
        guard
            let url = request.url,
            let scheme = url.scheme
            else {
                return false
            }
        
        return [ "http", "https" ].contains(scheme.lowercased()) && mock(for: request) != nil
    }
    
    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        if let mock = mock(for: request),
            let m = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest {
            URLProtocol.setProperty(mock, forKey: "mock", in: m)
            let r: NSURLRequest = m
            return r as URLRequest
        }
        
        return request
    }
    
    override func startLoading() {
        guard
            let url = self.request.url,
            let mock = URLProtocol.property(forKey: "mock", in: self.request) as? RequestMock
            else {
                return
            }
        
        let data = mock.mockHandler(mock, request) ?? String()
        
        var headers = mock.headers
        headers["Content-Length"] = String(format: "%lu", data.count)
        
        guard let response = HTTPURLResponse(url: url,
                                             statusCode: mock.statusCode,
                                             httpVersion: mock.httpVersion,
                                             headerFields: headers) else {
                                                return
                                            }
        
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: data.data(using: String.Encoding.utf8, allowLossyConversion: false)!)
        self.client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {
        
    }
}

typealias MockHandler = (RequestMock, URLRequest) -> String?

class RequestMock {
    let host: String
    let path: String
    var httpMethod: String
    var httpVersion: String
    var statusCode: Int
    var contentType: String
    var headers: [String: String]
    var mockHandler: MockHandler
    
    var variables = [String: String]()
    
    init(host: String,
         path: String,
         httpMethod: String,
         httpVersion: String = "HTTP/1.1",
         statusCode: Int = 200,
         contentType: String = "application/json",
         headers: [String: String] = [:],
         mockHandler: @escaping MockHandler) {
        self.host = host
        self.path = path
        self.httpMethod = httpMethod
        self.httpVersion = httpVersion
        self.statusCode = statusCode
        self.contentType = contentType
        self.headers = headers
        self.mockHandler = mockHandler
    }
    
    func canHandle(request: URLRequest) -> Bool {
        guard
            let url = request.url,
            let reqComps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                return false
        }
        
        if reqComps.host != host || request.httpMethod != httpMethod {
            return false
        }
        
        var mockPathComps = path.components(separatedBy: "/")
        var reqPathComps = reqComps.path.components(separatedBy: "/")
        
        if path.starts(with: "/") {
            mockPathComps = Array(mockPathComps.dropFirst())
        }
        
        if reqComps.path.starts(with: "/") {
            reqPathComps = Array(reqPathComps.dropFirst())
        }
        
        if mockPathComps.count == 1 && mockPathComps[0] == "*" {
            return true
        }
        
        if mockPathComps.count != reqPathComps.count {
            return false
        }
        
        var handles = true
        
        for i in 0..<mockPathComps.count {
            let mockPath = mockPathComps[i]
            let reqPath = reqPathComps[i]
            
            if let variable = self.variable(mockPath) {
                variables[variable] = reqPath
                
                continue
            }
            
            if mockPath != "*" && mockPath != reqPath {
                handles = false
                break
            }
        }
        
        return handles
    }
    
    private func variable(_ string: String) -> String? {
        if string.starts(with: "${") && string.last == "}" {
            let start = string.index(string.startIndex, offsetBy: 2)
            let end = string.index(string.endIndex, offsetBy: -1)
            let result = string[start..<end]
            return String (result)
        }
        
        return nil
    }
}