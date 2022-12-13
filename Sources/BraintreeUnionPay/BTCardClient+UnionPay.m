// MARK: - Objective-C File Imports for Package Managers
#if __has_include(<Braintree/BraintreeUnionPay.h>) // CocoaPods
#import <Braintree/BTCardClient+UnionPay.h>
#import <Braintree/BTCardCapabilities.h>
#import <Braintree/BTCardClient_Internal.h>
#import <Braintree/BraintreeCard.h>

#elif SWIFT_PACKAGE // SPM
#import <BraintreeUnionPay/BTCardClient+UnionPay.h>
#import <BraintreeUnionPay/BTCardCapabilities.h>
#import "../BraintreeCard/BTCardClient_Internal.h"
#import <BraintreeCard/BraintreeCard.h>

#else // Carthage
#import <BraintreeUnionPay/BTCardClient+UnionPay.h>
#import <BraintreeUnionPay/BTCardCapabilities.h>
#import <BraintreeCard/BTCardClient_Internal.h>
#import <BraintreeCard/BraintreeCard.h>

#endif

// MARK: - Swift File Imports for Package Managers
#if __has_include(<Braintree/Braintree-Swift.h>) // CocoaPods
#import <Braintree/Braintree-Swift.h>

#elif SWIFT_PACKAGE                              // SPM
/* Use @import for SPM support
 * See https://forums.swift.org/t/using-a-swift-package-in-a-mixed-swift-and-objective-c-project/27348
 */
@import BraintreeCore;

#elif __has_include("Braintree-Swift.h")         // CocoaPods for ReactNative
/* Use quoted style when importing Swift headers for ReactNative support
 * See https://github.com/braintree/braintree_ios/issues/671
 */
#import "Braintree-Swift.h"

#else                                            // Carthage
#import <BraintreeCore/BraintreeCore-Swift.h>
#endif

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
@implementation BTCardClient (UnionPay)
#pragma clang diagnostic pop

#pragma mark - Public methods

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)fetchCapabilities:(NSString *)cardNumber
               completion:(void (^)(BTCardCapabilities * _Nullable, NSError * _Nullable))completion {
    [self.apiClient fetchOrReturnRemoteConfiguration:^(BTConfiguration * _Nullable configuration, NSError * _Nullable error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        if (!configuration.isUnionPayEnabled) {
            NSError *error = [NSError errorWithDomain:BTCardClientErrorDomain code:BTCardClientErrorTypePaymentOptionNotEnabled userInfo:@{NSLocalizedDescriptionKey: @"UnionPay is not enabled for this merchant"}];
            completion(nil, error);
            return;
        }
        
        [self.apiClient GET:@"v1/payment_methods/credit_cards/capabilities"
                 parameters:@{@"credit_card[number]" : cardNumber}
                 completion:^(BTJSON * _Nullable body, __unused NSHTTPURLResponse * _Nullable response, NSError * _Nullable error)
         {
             if (error) {
                 [self sendUnionPayEvent:@"capabilities-failed"];
                 completion(nil, error);
             } else {
                 [self sendUnionPayEvent:@"capabilities-received"];

                 BTCardCapabilities *cardCapabilities = [[BTCardCapabilities alloc] init];
                 cardCapabilities.isUnionPay = [body[@"isUnionPay"] isTrue];
                 cardCapabilities.isDebit = [body[@"isDebit"] isTrue];
                 cardCapabilities.supportsTwoStepAuthAndCapture = [body[@"unionPay"][@"supportsTwoStepAuthAndCapture"] isTrue];
                 cardCapabilities.isSupported = [body[@"unionPay"][@"isSupported"] isTrue];
                 completion(cardCapabilities, nil);
             }
         }];
    }];
}
#pragma clang diagnostic pop

- (void)enrollCard:(BTCardRequest *)request
        completion:(nonnull void (^)(NSString * _Nullable, BOOL, NSError * _Nullable))completion {
    [self.apiClient fetchOrReturnRemoteConfiguration:^(BTConfiguration * _Nullable configuration, NSError * _Nullable error) {
        if (error) {
            [self invokeBlock:completion onMainThreadWithEnrollmentID:nil smsCodeRequired:NO error:error];
            return;
        }
        
        if (!configuration.isUnionPayEnabled) {
            NSError *error = [NSError errorWithDomain:BTCardClientErrorDomain code:BTCardClientErrorTypePaymentOptionNotEnabled userInfo:@{NSLocalizedDescriptionKey: @"UnionPay is not enabled for this merchant"}];
            [self invokeBlock:completion onMainThreadWithEnrollmentID:nil smsCodeRequired:NO error:error];
            return;
        }

        NSMutableDictionary *enrollmentParameters = [NSMutableDictionary dictionary];
        BTCard *card = request.card;
        if (card.number) {
            enrollmentParameters[@"number"] = card.number;
        }
        if (card.expirationMonth) {
            enrollmentParameters[@"expiration_month"] = card.expirationMonth;
        }
        if (card.expirationYear) {
            enrollmentParameters[@"expiration_year"] = card.expirationYear;
        }
        if (request.mobileCountryCode) {
            enrollmentParameters[@"mobile_country_code"] = request.mobileCountryCode;
        }
        if (request.mobilePhoneNumber) {
            enrollmentParameters[@"mobile_number"] = request.mobilePhoneNumber;
        }

        [self.apiClient POST:@"v1/union_pay_enrollments"
                  parameters:@{ @"union_pay_enrollment": enrollmentParameters }
                  completion:^(BTJSON * _Nullable body, __unused NSHTTPURLResponse * _Nullable response, NSError * _Nullable error)
         {
             if (error) {
                 if (error.code == BTCoreConstants.networkConnectionLostCode) {
                     [self.apiClient sendAnalyticsEvent:@"ios.union-pay.network-connection.failure"];
                 }
                 [self sendUnionPayEvent:@"enrollment-failed"];
                
                 NSError *callbackError = error;
                 NSHTTPURLResponse *response = error.userInfo[BTHTTPError.urlResponseKey];
                 if (response.statusCode == 422) {
                     callbackError = [NSError errorWithDomain:BTCardClientErrorDomain
                                                         code:BTCardClientErrorTypeCustomerInputInvalid
                                                     userInfo:[self.class validationErrorUserInfo:error.userInfo]];
                 }
                 
                 [self invokeBlock:completion onMainThreadWithEnrollmentID:nil smsCodeRequired:NO error:callbackError];
                 return;
             }

             [self sendUnionPayEvent:@"enrollment-succeeded"];
             BOOL smsCodeRequired = ![body[@"smsCodeRequired"] isNull] && [body[@"smsCodeRequired"] isTrue];
             [self invokeBlock:completion onMainThreadWithEnrollmentID:[body[@"unionPayEnrollmentId"] asString] smsCodeRequired:smsCodeRequired error:nil];
         }];
    }];
}

#pragma mark - Helper methods

- (void)invokeBlock:(nonnull void (^)(NSString * _Nullable, BOOL, NSError * _Nullable))completion onMainThreadWithEnrollmentID:(nullable NSString *)enrollmentID smsCodeRequired:(BOOL)smsCodeRequired error:(nullable NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(enrollmentID, smsCodeRequired, error);
    });
}

- (void)sendUnionPayEvent:(nonnull NSString *)event {
    NSString *fullEvent = [NSString stringWithFormat:@"ios.%@.unionpay.%@", self.apiClient.metadata.integrationString, event];
    [self.apiClient sendAnalyticsEvent:fullEvent];
}

@end
