//
//  File.swift
//  Budget
//
//  Created by Nate on 8/12/14.
//  Copyright (c) 2014 Nate. All rights reserved.
//

import UIKit
import Alamofire


public enum AccountInfoRetrevalError: Error {
    
    case locked(accessToken: String)
    case notConnected(accessToken: String)
    
}


public enum Environment {

    case development, production

}





public struct PlaidClient {

    public typealias JSON = [String : Any]

    ///Sign up at **Plaid.com** to receive a unique clienID
    private let clientIDToken: String
    
    ///Sign up at **Plaid.com** to receive a unique secretToken
    private let secretToken: String

    private let plaidURL: PlaidURL


    public init(clientIDToken: String, secretToken: String, environment: Environment) {
        self.clientIDToken = clientIDToken
        self.secretToken   = secretToken
        self.plaidURL = PlaidURL(environment: environment)
    }


    ///Fetches institutions from *Plaid*.
    /// - parameter completionHandler: returns a *NSHTTPURLResponse* and an Array of *PlaidInstitions*.
    public func plaidInstitutions(session: URLSession = URLSession.shared, completion: @escaping (_ response: URLResponse?, _ institutions: [PlaidInstitution]?, _ error: NSError?) -> Void) {
        session.dataTask(with: plaidURL.institutions()) { data, response, error in
            let json = self.decode(data: data) as? [JSON]
            completion(response, json?.flatMap { PlaidInstitution(institution: $0, source: .plaid) }, error as NSError?)
        }.resume()
    }

    
    ///Fetches institutions from *Intuit*
    /// - parameter count: The number of institutions to return.
    /// - parameter skip: The number of institutions to skip over.
    /// - parameter completionHandler: returns a *NSHTTPURLResponse* and an Array of *PlaidInstitions*
    public func intuitInstitutions(count: Int, skip: Int, session: URLSession = URLSession.shared, completion: @escaping (_ response: URLResponse?, _ institutions: [PlaidInstitution]?, _ error: NSError?) -> ()) {
        session.dataTask(with: plaidURL.intuit(clientID: clientIDToken, secret: secretToken, count: count, skip: skip)) { data, response, error in
            let json = self.decode(data: data) as? JSON
            let institutions = json?["results"] as? [JSON]
            completion(response, institutions?.flatMap { PlaidInstitution(institution: $0, source: .intuit) }, error as NSError?)
        }.resume()
    }


    ///Fetches a *Plaid* instution with a specified ID.
    /// - parameter id: The institution's id given by **Plaid.com**
    public func plaidInstitution(withID id: String, session: URLSession = URLSession.shared, completion: @escaping (_ response: URLResponse?, _ institution: PlaidInstitution?, _ error: NSError?) -> ()) {
        session.dataTask(with: plaidURL.institutions(id: id)) { data, response, error in
            if let json = self.decode(data: data) as? JSON {
                completion(response, PlaidInstitution(institution: json, source: .plaid), error as NSError?)
                return
            }
            completion(response, nil, error as NSError?)
        }.resume()
    }


    ///Logs in to a financial institutions
    /// - parameter institution: A *PlaidInstitution* object
    /// - parameter username: The user's username for the institution.
    /// - parameter password: The user's password for the institution.
    /// - parameter pin: The user's pin for the institution (if required)
    public func login(toInstitution institution: PlaidInstitution, username: String, password: String, pin: String? = nil, session: URLSession = URLSession.shared, completion: @escaping (_ response: URLResponse?, _ responseData: JSON?, _ error: NSError?) -> ()) {
        let url = plaidURL.connect(clientID: clientIDToken, secret: secretToken, institution: institution, username: username, password: password)
        session.dataTask(with: plaidURL.connect(clientID: clientIDToken, secret: secretToken, institution: institution, username: username, password: password)) { (data, response, error) in
            completion(response, self.decode(data: data) as? JSON, error as NSError?)
        }.resume()
    }

    
    public func submitMFAResponse(response: String, institution: PlaidInstitution, accessToken: String, session: URLSession = URLSession.shared, completion: @escaping (_ response: URLResponse?, _ responseData: JSON?, _ error: NSError?) -> ()) {

        let urlRequest = plaidURL.mfaResponse(clientID: clientIDToken, secret: secretToken, institution: institution, accessToken: accessToken, response: response)
        session.dataTask(with: urlRequest) { (data, response, error) in
            completion(response, self.decode(data: data) as? JSON, error as NSError?)
        }.resume()
    }

    
    public func patchInstitution(accessToken: String, username: String, password: String, pin: String, callBack: @escaping (_ response:HTTPURLResponse?, _ data: JSON?) -> ()) {
       
        let parameters: Parameters = ["client_id" : clientIDToken,
                             "secret" : secretToken,
                           "username" : username,
                           "password" : password,
                                "pin" : pin,
                       "access_token" : accessToken]

        Alamofire.request(plaidURL.baseURL + "/step", method: .patch, parameters: parameters, encoding: JSONEncoding.default).responseJSON { response in
            let data = response.result.value as? JSON
            callBack(response.response, data)
        }
    }
    
    
    public func patchSubmitMFAResponse(response: String, accessToken: String, callBack: @escaping (_ response:HTTPURLResponse?, _ data: JSON?) -> ()) {
        let parameters = ["client_id" : clientIDToken,
                             "secret" : secretToken,
//                           "username" : username,
//                           "password" : password,
//                                "pin" : pin,
                       "access_token" : accessToken,
                                "mfa" : response]
        Alamofire.request(plaidURL.baseURL + "/step", method: .patch, parameters: parameters, encoding: JSONEncoding.default).responseJSON { response in
            let data = response.result.value as? JSON
            callBack(response.response, data)
        }
    }
    
    
    
    
    
    public func downloadAccountData(accessToken: String, account: String, pending: Bool, fromDate: Date?, toDate: Date?, callBack: @escaping (_ response: HTTPURLResponse?, _ account: PlaidAccount?, _ plaidTransactions: [PlaidTransaction]?, _ error: AccountInfoRetrevalError?) -> ()) {
        var options: JSON = ["pending" : pending,
                             "account" : account]
        
        if let fromDate = fromDate {
            options["gte"] = DateFormatter.plaidDate(fromDate)
        }
        
        if let toDate = toDate {
            options["lte"] = DateFormatter.plaidDate(toDate)
        }
        
        let downloadCredentials: [String: Any] = ["client_id" : clientIDToken,
                                                           "secret" : secretToken,
                                                     "access_token" : accessToken,
                                                          "options" : options]
        
        Alamofire.request(plaidURL.baseURL + "/connect", parameters: downloadCredentials).responseJSON { response in
            guard let data = response.result.value as? JSON else { return }
            
            if let code = data["code"] as? Int {
                switch code {
    
                    case 1200...1209:
                        callBack(response.response!, nil, nil, .notConnected(accessToken:accessToken))
                    
                    default:
                        return
                }
            }
            
            if let transactions = data["transactions"] as? [JSON], let accounts = data["accounts"] as? [[String : Any]], let accountData = accounts.first {
                let plaidTransactions = transactions.map { PlaidTransaction(transaction: $0) }
                callBack(response.response!, PlaidAccount(account: accountData), plaidTransactions, nil)
            }
            callBack(response.response!, nil, nil, nil)
        }
    }


    private func decode(data: Data?) -> Any? {
        do {
            if let data = data {
                return try JSONSerialization.jsonObject(with: data, options: [.mutableContainers])
            }
        } catch {
            print("Could not decode Data: \(error)")
        }
        return nil
    }

}





public extension DateFormatter {
    
    public class var dateFormatter: DateFormatter {
        let dateFormatter = DateFormatter()
        
        dateFormatter.locale     = Locale(identifier: "en_US_PSIX")
        dateFormatter.dateFormat = "yyy-MM-dd"
        
        return dateFormatter
    }
    
    
    public class func plaidDate(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }
    
    
    public class func dateFromString(_ string: String) -> Date {
        return dateFormatter.date(from: string)!
    }
    
}










