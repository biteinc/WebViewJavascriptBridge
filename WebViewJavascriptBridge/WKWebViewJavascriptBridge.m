//
//  WKWebViewJavascriptBridge.m
//
//  Created by @LokiMeyburg on 10/15/14.
//  Copyright (c) 2014 @LokiMeyburg. All rights reserved.
//


#import "WKWebViewJavascriptBridge.h"

#ifdef USE_CRASHLYTICS
    #import <Crashlytics/Answers.h>
#endif

#if defined(supportsWKWebKit)

@implementation WKWebViewJavascriptBridge {
    WKWebView* _webView;
    id _webViewDelegate;
    long _uniqueId;
    WebViewJavascriptBridgeBase *_base;
    int _navigationCount;
}

/* API
 *****/

+ (void)enableLogging { [WebViewJavascriptBridgeBase enableLogging]; }

+ (instancetype)bridgeForWebView:(WKWebView*)webView handler:(WVJBHandler)handler {
    return [self bridgeForWebView:webView webViewDelegate:nil handler:handler];
}

+ (instancetype)bridgeForWebView:(WKWebView*)webView webViewDelegate:(NSObject<WKNavigationDelegate>*)webViewDelegate handler:(WVJBHandler)messageHandler {
    return [self bridgeForWebView:webView webViewDelegate:webViewDelegate handler:messageHandler resourceBundle:nil];
}

+ (instancetype)bridgeForWebView:(WKWebView*)webView webViewDelegate:(NSObject<WKNavigationDelegate>*)webViewDelegate handler:(WVJBHandler)messageHandler resourceBundle:(NSBundle*)bundle
{
    WKWebViewJavascriptBridge* bridge = [[self alloc] init];
    [bridge _setupInstance:webView webViewDelegate:webViewDelegate handler:messageHandler resourceBundle:bundle];
    [bridge reset];
    return bridge;
}

- (void)send:(id)data {
    [self send:data responseCallback:nil];
}

- (void)send:(id)data responseCallback:(WVJBResponseCallback)responseCallback {
    [_base sendData:data responseCallback:responseCallback handlerName:nil];
}

- (void)callHandler:(NSString *)handlerName {
    [self callHandler:handlerName data:nil responseCallback:nil];
}

- (void)callHandler:(NSString *)handlerName data:(id)data {
    [self callHandler:handlerName data:data responseCallback:nil];
}

- (void)callHandler:(NSString *)handlerName data:(id)data responseCallback:(WVJBResponseCallback)responseCallback {
    [_base sendData:data responseCallback:responseCallback handlerName:handlerName];
}

- (void)registerHandler:(NSString *)handlerName handler:(WVJBHandler)handler {
    _base.messageHandlers[handlerName] = [handler copy];
}

- (void)reset {
    [_base reset];
}

/* Internals
 ***********/

- (void)dealloc {
    _base = nil;
    _webView = nil;
    _webViewDelegate = nil;
    _webView.navigationDelegate = nil;
}


/* WKWebView Specific Internals
 ******************************/

- (void) _setupInstance:(WKWebView*)webView webViewDelegate:(id<WKNavigationDelegate>)webViewDelegate handler:(WVJBHandler)messageHandler resourceBundle:(NSBundle*)bundle{
    _webView = webView;
    _webViewDelegate = webViewDelegate;
    _webView.navigationDelegate = self;
    _base = [[WebViewJavascriptBridgeBase alloc] initWithHandler:(WVJBHandler)messageHandler resourceBundle:(NSBundle*)bundle];
    _base.delegate = self;
}


- (void)WKFlushMessageQueue {
    NSLog(@"WKFlushMessageQueue");
    NSString *js = [_base webViewJavascriptFetchQueyCommand];
    [_webView evaluateJavaScript:js completionHandler:^(NSString* result, NSError* error) {
        [_base flushMessageQueue:result];
#ifdef USE_CRASHLYTICS
        if (error) {
            [Answers logCustomEventWithName:@"bridge-eval-error"
                           customAttributes:@{@"method:": @"WKFlushMessageQueue",
                                              @"result": result ?: @"nil result",
                                              @"error": error.localizedDescription ?: @"nil error",
                                              @"js": js ?: @"nil js"}];
        }
#endif
    }];
}

- (void)setJsVersion:(NSString *)jsVersion {
    _jsVersion = jsVersion;
    _navigationCount = 0;
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(null_unspecified WKNavigation *)navigation {
    NSLog(@"DID COMMIT NAVIGATION: %@", navigation);
    if (_navigationCount) {
#ifdef USE_CRASHLYTICS
        [Answers logCustomEventWithName:@"bridge-did-commit-navigation"
                       customAttributes:@{@"webview.URL": webView.URL ?: @"nil url",
                                          @"navigation": navigation ?: @"nil navigation"}];
#endif
    }
    _navigationCount++;
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    NSLog(@"CONTENT DID TERMINATE");
#ifdef USE_CRASHLYTICS
    [Answers logCustomEventWithName:@"bridge-did-terminate"
                   customAttributes:@{@"webview.URL": webView.URL ?: @"nil url"}];
#endif
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    if (webView != _webView) { return; }

    _base.numRequestsLoading--;
    
    if (_base.numRequestsLoading == 0) {
        NSString *js = [_base webViewJavascriptCheckCommand];
        [webView evaluateJavaScript:js completionHandler:^(NSString *result, NSError *error) {
            [_base injectJavascriptFile:![result boolValue]];
#ifdef USE_CRASHLYTICS
            if (error) {
                [Answers logCustomEventWithName:@"bridge-eval-error"
                               customAttributes:@{@"method": @"didFinishNavigation",
                                                  @"result": result ?: @"nil result",
                                                  @"error": error.localizedDescription ?: @"nil error",
                                                  @"js": js ?: @"nil js"}];
            }
#endif
        }];
    }
    
    __strong typeof(_webViewDelegate) strongDelegate = _webViewDelegate;
    if (strongDelegate && [strongDelegate respondsToSelector:@selector(webView:didFinishNavigation:)]) {
        [strongDelegate webView:webView didFinishNavigation:navigation];
    }
}


- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (webView != _webView) { return; }
    NSURL *url = navigationAction.request.URL;
    __strong typeof(_webViewDelegate) strongDelegate = _webViewDelegate;

    if ([_base isCorrectProcotocolScheme:url]) {
        if ([_base isCorrectHost:url]) {
            [self WKFlushMessageQueue];
        } else {
            [_base logUnkownMessage:url];
        }
        [webView stopLoading];
    }
    
    if (strongDelegate && [strongDelegate respondsToSelector:@selector(webView:decidePolicyForNavigationAction:decisionHandler:)]) {
        [_webViewDelegate webView:webView decidePolicyForNavigationAction:navigationAction decisionHandler:decisionHandler];
    } else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    if (webView != _webView) { return; }
    
    _base.numRequestsLoading++;
    
    __strong typeof(_webViewDelegate) strongDelegate = _webViewDelegate;
    if (strongDelegate && [strongDelegate respondsToSelector:@selector(webView:didStartProvisionalNavigation:)]) {
        [strongDelegate webView:webView didStartProvisionalNavigation:navigation];
    }
}


- (void)webView:(WKWebView *)webView
didFailNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    if (webView != _webView) { return; }
    
    _base.numRequestsLoading--;
    
    __strong typeof(_webViewDelegate) strongDelegate = _webViewDelegate;
    if (strongDelegate && [strongDelegate respondsToSelector:@selector(webView:didFailNavigation:withError:)]) {
        [strongDelegate webView:webView didFailNavigation:navigation withError:error];
    }
}

- (NSString*) _evaluateJavascript:(NSString*)javascriptCommand
{
    [_webView evaluateJavaScript:javascriptCommand completionHandler:^(NSString *result, NSError *error) {
#ifdef USE_CRASHLYTICS
        if (error) {
            [Answers logCustomEventWithName:@"bridge-eval-error"
                           customAttributes:@{@"method:": @"_evaluateJavascript",
                                              @"result": result ?: @"nil result",
                                              @"error": error.localizedDescription ?: @"nil error",
                                              @"js": javascriptCommand ?: @"nil js"}];
        }
#endif
    }];
    return NULL;
}



@end


#endif
