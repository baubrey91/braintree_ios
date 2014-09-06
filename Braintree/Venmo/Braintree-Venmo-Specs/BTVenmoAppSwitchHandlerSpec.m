#import "BTVenmoErrors.h"
#import "BTVenmoAppSwitchHandler.h"
#import "BTVenmoAppSwitchHandler_Internal.h"
#import "BTVenmoAppSwitchReturnURL.h"
#import "BTVenmoAppSwitchRequestURL.h"
#import "BTClient+BTVenmo.h"
#import "BTClient_Metadata.h"

SpecBegin(BTVenmoAppSwitchHandler)

describe(@"sharedHandler", ^{

    it(@"returns one and only one instance", ^{
        expect([BTVenmoAppSwitchHandler sharedHandler]).to.beIdenticalTo([BTVenmoAppSwitchHandler sharedHandler]);
    });

});

describe(@"isAvailableForClient:", ^{

    __block id client;
    __block id venmoAppSwitchRequestURL;

    beforeEach(^{
        client = [OCMockObject mockForClass:[BTClient class]];
        venmoAppSwitchRequestURL = [OCMockObject mockForClass:[BTVenmoAppSwitchRequestURL class]];
    });

    afterEach(^{
        [client verify];
        [client stopMocking];
        [venmoAppSwitchRequestURL verify];
        [venmoAppSwitchRequestURL stopMocking];
    });

    it(@"returns YES if [BTVenmoAppSwitchRequestURL isAppSwitchAvailable] and venmo status is production", ^{
        [[[client stub] andReturnValue:OCMOCK_VALUE(BTVenmoStatusProduction)] btVenmo_status];
        [[[venmoAppSwitchRequestURL stub] andReturnValue:@YES] isAppSwitchAvailable];
        expect([BTVenmoAppSwitchHandler isAvailableForClient:client]).to.beTruthy();
    });

    it(@"returns YES if [BTVenmoAppSwitchRequestURL isAppSwitchAvailable] and venmo status is offline", ^{
        [[[client stub] andReturnValue:OCMOCK_VALUE(BTVenmoStatusOffline)] btVenmo_status];
        [[[venmoAppSwitchRequestURL stub] andReturnValue:@YES] isAppSwitchAvailable];
        expect([BTVenmoAppSwitchHandler isAvailableForClient:client]).to.beTruthy();
    });

    it(@"returns NO if venmo status is off", ^{
        [[[client stub] andReturnValue:OCMOCK_VALUE(BTVenmoStatusOff)] btVenmo_status];
        [[[venmoAppSwitchRequestURL stub] andReturnValue:@YES] isAppSwitchAvailable];
        expect([BTVenmoAppSwitchHandler isAvailableForClient:client]).to.beFalsy();
    });

    it(@"returns NO if [BTVenmoAppSwitchRequestURL isAppSwitchAvailable] returns NO", ^{
        [[[client stub] andReturnValue:OCMOCK_VALUE(BTVenmoStatusProduction)] btVenmo_status];
        [[[venmoAppSwitchRequestURL stub] andReturnValue:@NO] isAppSwitchAvailable];
        expect([BTVenmoAppSwitchHandler isAvailableForClient:client]).to.beFalsy();
    });

});


describe(@"An instance", ^{
    __block BTVenmoAppSwitchHandler *handler;
    __block id client;
    __block id delegate;

    beforeEach(^{
        handler = [[BTVenmoAppSwitchHandler alloc] init];
        client = [OCMockObject mockForClass:[BTClient class]];
        delegate = [OCMockObject mockForProtocol:@protocol(BTAppSwitchingDelegate)];

        [[[client stub] andReturn:client] copyWithMetadata:OCMOCK_ANY];
        [[client stub] postAnalyticsEvent:OCMOCK_ANY];

    });

    afterEach(^{
        [client verify];
        [client stopMocking];

        [delegate verify];
        [delegate stopMocking];
    });

    describe(@"canHandleReturnURL:sourceApplication:", ^{

        __block id mockVenmoAppSwitchReturnURL;
        NSString *testSourceApplication = @"a-source.app.App";
        NSURL *testURL = [NSURL URLWithString:@"another-scheme://a-host"];

        beforeEach(^{
            mockVenmoAppSwitchReturnURL = [OCMockObject mockForClass:[BTVenmoAppSwitchReturnURL class]];
        });

        afterEach(^{
            [mockVenmoAppSwitchReturnURL verify];
            [mockVenmoAppSwitchReturnURL stopMocking];
        });

        it(@"returns YES if [BTVenmoAppSwitchReturnURL isValidURL:sourceApplication:] returns YES", ^{
            [[[mockVenmoAppSwitchReturnURL expect] andReturnValue:@YES] isValidURL:testURL sourceApplication:testSourceApplication];

            BOOL handled = [handler canHandleReturnURL:testURL sourceApplication:testSourceApplication];

            expect(handled).to.beTruthy();
        });

        it(@"returns NO if [BTVenmoAppSwitchReturnURL isValidURL:sourceApplication:] returns NO", ^{
            [[[mockVenmoAppSwitchReturnURL expect] andReturnValue:@NO] isValidURL:testURL sourceApplication:testSourceApplication];

            BOOL handled = [handler canHandleReturnURL:testURL sourceApplication:testSourceApplication];

            expect(handled).to.beFalsy();
        });
    });

    describe(@"initiateAppSwitchWithClient:delegate:", ^{

        it(@"returns NO if client has `btVenmo_status` BTVenmoStatusOff", ^{

            [[delegate expect] appSwitcher:handler didFailWithError:[OCMArg checkWithBlock:^BOOL(id obj) {
                NSError *error = (NSError *)obj;
                expect(error.domain).to.equal(BTVenmoErrorDomain);
                expect(error.code).to.equal(BTVenmoErrorAppSwitchDisabled);
                return YES;
            }]];

            [[[client expect] andReturnValue:OCMOCK_VALUE(BTVenmoStatusOff)] btVenmo_status];

            [handler initiateAppSwitchWithClient:client delegate:delegate];

        });
    });

    describe(@"handleReturnURL:", ^{

        __block id appSwitchReturnURL;
        __block id paymentMethod;

        NSURL *returnURL = [NSURL URLWithString:@"scheme://host/x"];

        beforeEach(^{
            delegate = [OCMockObject mockForProtocol:@protocol(BTAppSwitchingDelegate)];
            handler.delegate = delegate;
            client = [OCMockObject mockForClass:[BTClient class]];
            handler.client = client;

            appSwitchReturnURL = [OCMockObject mockForClass:[BTVenmoAppSwitchReturnURL class]];
            [[[appSwitchReturnURL stub] andReturn:appSwitchReturnURL] alloc];
            __unused id _ = [[[appSwitchReturnURL stub] andReturn:appSwitchReturnURL] initWithURL:returnURL];

            paymentMethod = [OCMockObject mockForClass:[BTPaymentMethod class]];
            [[[paymentMethod stub] andReturn:@"a-nonce" ] nonce];

            [[[appSwitchReturnURL stub] andReturn:paymentMethod] paymentMethod];
        });

        afterEach(^{
            [appSwitchReturnURL verify];
            [appSwitchReturnURL stopMocking];
        });

        describe(@"with valid URL and with Venmo set to production", ^{

            beforeEach(^{
                [[[appSwitchReturnURL stub] andReturnValue:OCMOCK_VALUE(BTVenmoAppSwitchReturnURLStateSucceeded)] state];
                [[[client stub] andReturnValue:OCMOCK_VALUE(BTVenmoStatusProduction)] btVenmo_status];
            });

            it(@"performs fetchPaymentMethodWithNonce:success:failure:", ^{
                [[delegate expect] appSwitcherWillCreatePaymentMethod:handler];
                [[client expect] postAnalyticsEvent:@"ios.venmo.appswitch.handle.authorized"];
                [[client expect] fetchPaymentMethodWithNonce:@"a-nonce" success:OCMOCK_ANY failure:OCMOCK_ANY];

                // TODO - examine blocks passed to fetchPaymentMethodWithNonce
                // [[client expect] fetchPaymentMethodWithNonce:@"a-nonce" success:OCMOCK_ANY failure:OCMOCK_ANY];
                // [[delegate expect] appSwitcher:handler didCreatePaymentMethod:paymentMethod];

                [handler handleReturnURL:returnURL];
            });

        });
    });
});


SpecEnd
