/*
 Copyright (c) 2017, Joel Levin
 All rights reserved.

 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 Neither the name of JLRoutes nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "JLRoutes.h"
#import "JLRRouteDefinition.h"
#import "JLRParsingUtilities.h"


NSString *const JLRoutePatternKey = @"JLRoutePattern";
NSString *const JLRouteURLKey = @"JLRouteURL";
NSString *const JLRouteSchemeKey = @"JLRouteScheme";
NSString *const JLRouteWildcardComponentsKey = @"JLRouteWildcardComponents";
// 全局 router 的 scheme
NSString *const JLRoutesGlobalRoutesScheme = @"JLRoutesGlobalRoutesScheme";


// 路由 map
// key 是 scheme，value 是 JSRoutes 对象
// 一个组件对应一个 scheme
static NSMutableDictionary *routeControllersMap = nil;

// global options
static BOOL verboseLoggingEnabled = NO;
static BOOL shouldDecodePlusSymbols = YES;
static BOOL alwaysTreatsHostAsPathComponent = NO;


@interface JLRoutes ()

// 路由数组，保存 <JLRRouteDefinition> 对象
// JLRoutes的数组里面，会按照路由的优先级进行排列，优先级高的排列在前面。
@property (nonatomic, strong) NSMutableArray *mutableRoutes;
@property (nonatomic, strong) NSString *scheme;

@end


#pragma mark -

@implementation JLRoutes

- (instancetype)init
{
    if ((self = [super init])) {
        self.mutableRoutes = [NSMutableArray array];
    }
    return self;
}

- (NSString *)description
{
    return [self.mutableRoutes description];
}

// 返回所有的路由
+ (NSDictionary <NSString *, NSArray <JLRRouteDefinition *> *> *)allRoutes;
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    
    for (NSString *namespace in [routeControllersMap copy]) {
        JLRoutes *routesController = routeControllersMap[namespace];
        dictionary[namespace] = [routesController.mutableRoutes copy];
    }
    
    return [dictionary copy];
}


#pragma mark - Routing Schemes

// 初始化
+ (instancetype)globalRoutes
{
    return [self routesForScheme:JLRoutesGlobalRoutesScheme];
}

+ (instancetype)routesForScheme:(NSString *)scheme
{
    JLRoutes *routesController = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        routeControllersMap = [[NSMutableDictionary alloc] init];
    });
    
    if (!routeControllersMap[scheme]) {
        routesController = [[self alloc] init];
        routesController.scheme = scheme;
        routeControllersMap[scheme] = routesController;
    }
    
    routesController = routeControllersMap[scheme];
    
    return routesController;
}

// 接触注册，直接从 map 中移除即可
+ (void)unregisterRouteScheme:(NSString *)scheme
{
    [routeControllersMap removeObjectForKey:scheme];
}

+ (void)unregisterAllRouteSchemes
{
    [routeControllersMap removeAllObjects];
}


#pragma mark - Registering Routes

// 注册路由

- (void)addRoute:(JLRRouteDefinition *)routeDefinition
{
    [self _registerRoute:routeDefinition];
}

- (void)addRoute:(NSString *)routePattern handler:(BOOL (^)(NSDictionary<NSString *, id> *parameters))handlerBlock
{
    [self addRoute:routePattern priority:0 handler:handlerBlock];
}

- (void)addRoutes:(NSArray<NSString *> *)routePatterns handler:(BOOL (^)(NSDictionary<NSString *, id> *parameters))handlerBlock
{
    for (NSString *routePattern in routePatterns) {
        [self addRoute:routePattern handler:handlerBlock];
    }
}

- (void)addRoute:(NSString *)routePattern priority:(NSUInteger)priority handler:(BOOL (^)(NSDictionary<NSString *, id> *parameters))handlerBlock
{
    // 解析 url 中的可选路径
    NSArray <NSString *> *optionalRoutePatterns = [JLRParsingUtilities expandOptionalRoutePatternsForPattern:routePattern];
    
    // 创建 JLRRouteDefinition 对象
    JLRRouteDefinition *route = [[JLRRouteDefinition alloc] initWithScheme:self.scheme pattern:routePattern priority:priority handlerBlock:handlerBlock];
    
    // 如果包含可选路径
    if (optionalRoutePatterns.count > 0) {
        // there are optional params, parse and add them
        for (NSString *pattern in optionalRoutePatterns) {
            [self _verboseLog:@"Automatically created optional route: %@", route];
            JLRRouteDefinition *optionalRoute = [[JLRRouteDefinition alloc] initWithScheme:self.scheme pattern:pattern priority:priority handlerBlock:handlerBlock];
            [self _registerRoute:optionalRoute];
        }
        return;
    }
    
    [self _registerRoute:route];
}

// 移除路由
- (void)removeRoute:(NSString *)routePattern
{
    if (![routePattern hasPrefix:@"/"]) {
        routePattern = [NSString stringWithFormat:@"/%@", routePattern];
    }
    
    NSInteger routeIndex = NSNotFound;
    NSInteger index = 0;
    
    for (JLRRouteDefinition *route in [self.mutableRoutes copy]) {
        if ([route.pattern isEqualToString:routePattern]) {
            routeIndex = index;
            break;
        }
        index++;
    }
    
    if (routeIndex != NSNotFound) {
        [self.mutableRoutes removeObjectAtIndex:(NSUInteger)routeIndex];
    }
}

- (void)removeAllRoutes
{
    [self.mutableRoutes removeAllObjects];
}

- (void)setObject:(id)handlerBlock forKeyedSubscript:(NSString *)routePatten
{
    [self addRoute:routePatten handler:handlerBlock];
}

- (NSArray <JLRRouteDefinition *> *)routes;
{
    return [self.mutableRoutes copy];
}

#pragma mark - Routing URLs

// 判断能否进行路由

+ (BOOL)canRouteURL:(NSURL *)URL
{
    return [[self _routesControllerForURL:URL] canRouteURL:URL];
}

- (BOOL)canRouteURL:(NSURL *)URL
{
    return [self _routeURL:URL withParameters:nil executeRouteBlock:NO];
}


// 开始路由

+ (BOOL)routeURL:(NSURL *)URL
{
    return [[self _routesControllerForURL:URL] routeURL:URL];
}

- (BOOL)routeURL:(NSURL *)URL
{
    return [self _routeURL:URL withParameters:nil executeRouteBlock:YES];
}

+ (BOOL)routeURL:(NSURL *)URL withParameters:(NSDictionary *)parameters
{
    return [[self _routesControllerForURL:URL] routeURL:URL withParameters:parameters];
}

- (BOOL)routeURL:(NSURL *)URL withParameters:(NSDictionary *)parameters
{
    return [self _routeURL:URL withParameters:parameters executeRouteBlock:YES];
}


#pragma mark - Private

+ (instancetype)_routesControllerForURL:(NSURL *)URL
{
    if (URL == nil) {
        return nil;
    }
    
    return routeControllersMap[URL.scheme] ?: [JLRoutes globalRoutes];
}

// 私有方法
// 根据优先级注册一个路由
// 数组实现一个优先队列
// 这里需要遍历一遍，性能不是很高
- (void)_registerRoute:(JLRRouteDefinition *)route
{
    // 优先级默认为 0
    if (route.priority == 0 || self.mutableRoutes.count == 0) {
        [self.mutableRoutes addObject:route];
    } else {
        // 优先级比 0 高的情况
        NSUInteger index = 0;
        BOOL addedRoute = NO;
        
        // search through existing routes looking for a lower priority route than this one
        for (JLRRouteDefinition *existingRoute in [self.mutableRoutes copy]) {
            if (existingRoute.priority < route.priority) {
                // if found, add the route after it
                [self.mutableRoutes insertObject:route atIndex:index];
                addedRoute = YES;
                break;
            }
            index++;
        }
        
        // if we weren't able to find a lower priority route, this is the new lowest priority route (or same priority as self.routes.lastObject) and should just be added
        if (!addedRoute) {
            [self.mutableRoutes addObject:route];
        }
    }
}

// 开始路由
// 返回能否进行路由

- (BOOL)_routeURL:(NSURL *)URL withParameters:(NSDictionary *)parameters executeRouteBlock:(BOOL)executeRouteBlock
{
    if (!URL) {
        return NO;
    }
    
    [self _verboseLog:@"Trying to route URL %@", URL];
    
    BOOL didRoute = NO;
    
    // 进行路由，要创建 JLRRouteRequest 对象
    
    JLRRouteRequest *request = [[JLRRouteRequest alloc] initWithURL:URL alwaysTreatsHostAsPathComponent:alwaysTreatsHostAsPathComponent];
    
    
    // 遍历进行检查
    
    for (JLRRouteDefinition *route in [self.mutableRoutes copy]) {
        // check each route for a matching response
        // 查看是否满足某一注册过的路由
        JLRRouteResponse *response = [route routeResponseForRequest:request decodePlusSymbols:shouldDecodePlusSymbols];
        if (!response.isMatch) {
            continue;
        }
        
        [self _verboseLog:@"Successfully matched %@", route];
        
        // 没有保护 block
        if (!executeRouteBlock) {
            // if we shouldn't execute but it was a match, we're done now
            return YES;
        }
        
        // configure the final parameters
        // 设置参数
        NSMutableDictionary *finalParameters = [NSMutableDictionary dictionary];
        [finalParameters addEntriesFromDictionary:response.parameters];
        [finalParameters addEntriesFromDictionary:parameters];
        [self _verboseLog:@"Final parameters are %@", finalParameters];
        
        // 调用路由 block
        didRoute = [route callHandlerBlockWithParameters:finalParameters];
        
        if (didRoute) {
            // if it was routed successfully, we're done
            break;
        }
    }
    
    if (!didRoute) {
        [self _verboseLog:@"Could not find a matching route"];
    }
    
    // if we couldn't find a match and this routes controller specifies to fallback and its also not the global routes controller, then...
    // 如果在当前路由规则里面没有找到匹配的路由，当前路由不是global 的，并且允许降级到global里面去查找，那么我们继续在global的路由规则里面去查找。
    if (!didRoute && self.shouldFallbackToGlobalRoutes && ![self _isGlobalRoutesController]) {
        [self _verboseLog:@"Falling back to global routes..."];
        didRoute = [[JLRoutes globalRoutes] _routeURL:URL withParameters:parameters executeRouteBlock:executeRouteBlock];
    }
    
    // if, after everything, we did not route anything and we have an unmatched URL handler, then call it
    // 未匹配 block
    // 最后，依旧没有找到任何能匹配的，如果有unmatched URL handler，调用这个闭包进行最后的处理。
    if (!didRoute && executeRouteBlock && self.unmatchedURLHandler) {
        [self _verboseLog:@"Falling back to the unmatched URL handler"];
        self.unmatchedURLHandler(self, URL, parameters);
    }
    
    return didRoute;
}

- (BOOL)_isGlobalRoutesController
{
    return [self.scheme isEqualToString:JLRoutesGlobalRoutesScheme];
}

- (void)_verboseLog:(NSString *)format, ...
{
    if (!verboseLoggingEnabled || format.length == 0) {
        return;
    }
    
    va_list argsList;
    va_start(argsList, format);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-nonliteral"
    NSString *formattedLogMessage = [[NSString alloc] initWithFormat:format arguments:argsList];
#pragma clang diagnostic pop
    
    va_end(argsList);
    NSLog(@"[JLRoutes]: %@", formattedLogMessage);
}

@end


#pragma mark - Global Options

@implementation JLRoutes (GlobalOptions)

+ (void)setVerboseLoggingEnabled:(BOOL)loggingEnabled
{
    verboseLoggingEnabled = loggingEnabled;
}

+ (BOOL)isVerboseLoggingEnabled
{
    return verboseLoggingEnabled;
}

+ (void)setShouldDecodePlusSymbols:(BOOL)shouldDecode
{
    shouldDecodePlusSymbols = shouldDecode;
}

+ (BOOL)shouldDecodePlusSymbols
{
    return shouldDecodePlusSymbols;
}

+ (void)setAlwaysTreatsHostAsPathComponent:(BOOL)treatsHostAsPathComponent
{
    alwaysTreatsHostAsPathComponent = treatsHostAsPathComponent;
}

+ (BOOL)alwaysTreatsHostAsPathComponent
{
    return alwaysTreatsHostAsPathComponent;
}

@end


#pragma mark - Deprecated

// deprecated
NSString *const kJLRoutePatternKey = @"JLRoutePattern";
NSString *const kJLRouteURLKey = @"JLRouteURL";
NSString *const kJLRouteSchemeKey = @"JLRouteScheme";
NSString *const kJLRouteWildcardComponentsKey = @"JLRouteWildcardComponents";
NSString *const kJLRoutesGlobalRoutesScheme = @"JLRoutesGlobalRoutesScheme";

NSString *const kJLRouteNamespaceKey = @"JLRouteScheme"; // deprecated
NSString *const kJLRoutesGlobalNamespaceKey = @"JLRoutesGlobalRoutesScheme"; // deprecated

@implementation JLRoutes (Deprecated)

+ (void)addRoute:(NSString *)routePattern handler:(BOOL (^)(NSDictionary<NSString *, id> *parameters))handlerBlock
{
    [[self globalRoutes] addRoute:routePattern handler:handlerBlock];
}

+ (void)addRoute:(NSString *)routePattern priority:(NSUInteger)priority handler:(BOOL (^)(NSDictionary<NSString *, id> *parameters))handlerBlock
{
    [[self globalRoutes] addRoute:routePattern priority:priority handler:handlerBlock];
}

+ (void)addRoutes:(NSArray<NSString *> *)routePatterns handler:(BOOL (^)(NSDictionary<NSString *, id> *parameters))handlerBlock
{
    [[self globalRoutes] addRoutes:routePatterns handler:handlerBlock];
}

+ (void)removeRoute:(NSString *)routePattern
{
    [[self globalRoutes] removeRoute:routePattern];
}

+ (void)removeAllRoutes
{
    [[self globalRoutes] removeAllRoutes];
}

+ (BOOL)canRouteURL:(NSURL *)URL withParameters:(NSDictionary *)parameters
{
    return [[self globalRoutes] canRouteURL:URL];
}

- (BOOL)canRouteURL:(NSURL *)URL withParameters:(NSDictionary *)parameters
{
    return [self canRouteURL:URL];
}

@end
