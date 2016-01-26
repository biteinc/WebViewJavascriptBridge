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
    NSNumber *_buildNumber;
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

    _buildNumber = [[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"];
}


- (void)WKFlushMessageQueue {
    NSLog(@"WKFlushMessageQueue");
    NSString *js = [_base webViewJavascriptFetchQueyCommand];
    [_webView evaluateJavaScript:js completionHandler:^(NSString* result, NSError* error) {
        [_base flushMessageQueue:result];
        if (error) {
            GCNLogError(@"Bridge-Eval-Error L:103!!!\nMethod: WKFlushMessageQueue\nResult: %@\nError: %@\nJS: %@",
                        result ?: @"nil result",
                        error.localizedDescription ?: @"nil error",
                        js ?: @"nil js");
#ifdef USE_CRASHLYTICS
            [Answers logCustomEventWithName:@"bridge-eval-error"
                           customAttributes:@{@"method:": @"WKFlushMessageQueue",
                                              @"result": result ?: @"nil result",
                                              @"error": error.localizedDescription ?: @"nil error",
                                              @"js": js ?: @"nil js",
                                              @"build": _buildNumber}];
#endif
        }
    }];
}

- (void)setJsVersion:(NSString *)jsVersion {
    _jsVersion = jsVersion;
    _navigationCount = 0;
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(null_unspecified WKNavigation *)navigation {
    GCNLogError(@"DID COMMIT NAVIGATION: URL: %@, %@ %d", webView.URL, navigation, _navigationCount);
    if (_navigationCount) {
#ifdef USE_CRASHLYTICS
        [Answers logCustomEventWithName:@"bridge-did-commit-navigation"
                       customAttributes:@{@"webview.URL": webView.URL ?: @"nil url",
                                          @"navigation": navigation ?: @"nil navigation",
                                          @"build": _buildNumber}];
#endif
    }
    _navigationCount++;
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    GCNLogError(@"CONTENT DID TERMINATE %@", webView.URL);
#ifdef USE_CRASHLYTICS
    [Answers logCustomEventWithName:@"bridge-did-terminate"
                   customAttributes:@{@"webview.URL": webView.URL ?: @"nil url",
                                      @"build": _buildNumber}];
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
            if (error) {
                GCNLogError(@"Bridge-Eval-Error L:154!!!\nMethod: didFinishNavigation\nResult: %@\nError: %@\nJS: %@",
                            result ?: @"nil result",
                            error.localizedDescription ?: @"nil error",
                            js ?: @"nil js");
#ifdef USE_CRASHLYTICS
                [Answers logCustomEventWithName:@"bridge-eval-error"
                               customAttributes:@{@"method": @"didFinishNavigation",
                                                  @"result": result ?: @"nil result",
                                                  @"error": error.localizedDescription ?: @"nil error",
                                                  @"js": js ?: @"nil js",
                                                  @"build": _buildNumber}];
#endif
            }
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
        if (error) {
            GCNLogError(@"Bridge-Eval-Error L:228!!!\nMethod: _evaluateJavascript\nResult: %@\nError: %@\nJS: %@",
                        result ?: @"nil result",
                        error.localizedDescription ?: @"nil error",
                        javascriptCommand ?: @"nil js");
#ifdef USE_CRASHLYTICS
            [Answers logCustomEventWithName:@"bridge-eval-error"
                           customAttributes:@{@"method:": @"_evaluateJavascript",
                                              @"result": result ?: @"nil result",
                                              @"error": error.localizedDescription ?: @"nil error",
                                              @"js": javascriptCommand ?: @"nil js",
                                              @"build": _buildNumber}];
#endif
        }
    }];
    return NULL;
}

@end


#endif
