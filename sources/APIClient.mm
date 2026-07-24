#import "HeaderAPI.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "MBProgressHUD.h"
#import "FTNotificationIndicator.h"
#import "RRReachability.h"

typedef void (*VoidImp)(id, SEL, ...);
typedef id (*IdImp)(id, SEL, ...);
typedef void (*MsgSendFunc)(void);
typedef void (*TrampolineFunc)(id, SEL, id);
typedef void (*ImpFuncType)(id, SEL, id); 

static void __attribute__((noinline)) trampoline_jump(void (*func)(id, SEL, id), id t, SEL s, id o) {
    volatile uintptr_t func_addr = (uintptr_t)func;
    volatile uintptr_t mask = 0xDEADBEEF;
    uintptr_t masked = func_addr ^ mask;
    uintptr_t unmasked = masked ^ mask;
    ((void (*)(id, SEL, id))unmasked)(t, s, o);
}

@interface APIClient : NSObject
@property (nonatomic, strong) NSString *contactLink;
@property (nonatomic, assign) BOOL isMaintenance;
@property (nonatomic, strong) NSMutableDictionary *memoryGap;
@property (nonatomic, strong) MBProgressHUD *hud;

+ (instancetype)sharedInstance;
- (void)startProcess;
@end

@implementation APIClient

- (void)vm_exec_selector:(SEL)sel target:(id)target object:(id)obj {
    [self vm_entry_point:sel target:target object:obj];
}

- (void)vm_entry_point:(SEL)s target:(id)t object:(id)o {
    if (!t || !s) return;
    
    volatile uintptr_t imp_addr = (uintptr_t)class_getMethodImplementation([t class], s);
    void (*volatile target_func)(id, SEL, id) = (void (*)(id, SEL, id))imp_addr;
    
    trampoline_jump(target_func, t, s, o);
}

- (id)vm_exec_return:(SEL)sel target:(id)target {
    if ([target respondsToSelector:sel]) {
        IMP imp = [target methodForSelector:sel];
        id (*func)(id, SEL) = (id (*)(id, SEL))imp;
        return func(target, sel);
    }
    return nil;
}

+ (instancetype)sharedInstance {
    static APIClient *sharedInstance = nil;
    static dispatch_once_t onceToken;
    
    void (*dispatch_once_ptr)(dispatch_once_t *, dispatch_block_t) = (void(*)(dispatch_once_t *, dispatch_block_t))dispatch_once;
    
    dispatch_once_ptr(&onceToken, ^{
        sharedInstance = [[APIClient alloc] init];
        SEL setC = sel_registerName("setContactLink:");
        ((void(*)(id, SEL, id))objc_msgSend)(sharedInstance, setC, @"");
        
        SEL setM = sel_registerName("setMemoryGap:");
        Class dictCls = objc_getClass("NSMutableDictionary");
        SEL dictSel = sel_registerName("dictionary");
        id dict = ((id(*)(id, SEL))objc_msgSend)(dictCls, dictSel);
        ((void(*)(id, SEL, id))objc_msgSend)(sharedInstance, setM, dict);
    });
    return sharedInstance;
}

+ (void)load {
    unsigned long long delay = 1;
    dispatch_time_t d_time = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
    
    dispatch_after(d_time, dispatch_get_main_queue(), ^{
        Class cls = objc_getClass("APIClient");
        SEL sharedSel = sel_registerName("sharedInstance");
        id instance = ((id(*)(id, SEL))objc_msgSend)(cls, sharedSel);
        
        SEL startSel = sel_registerName("startProcess");
        ((void(*)(id, SEL))objc_msgSend)(instance, startSel);
    });
}

- (UIViewController *)getTopViewController {
    __block UIViewController *resultVC = nil;
    
    void (^finderBlock)(void) = ^{
        UIWindow *foundWindow = nil;
        Class appCls = objc_getClass("UIApplication");
        SEL sharedAppSel = sel_registerName("sharedApplication");
        id sharedApp = ((id(*)(id, SEL))objc_msgSend)(appCls, sharedAppSel);
        
        void *labels[] = { &&StateInit, &&StateIOS13, &&StateSceneLoop, &&StateWinLoop, &&StateLegacy, &&StateLegacyLoop, &&StateFinal, &&StateEnd };
        volatile int state = 0;
        
    Dispatch:
        goto *labels[state];
        
    StateInit:
        if (@available(iOS 13.0, *)) {
            state = 1;
        } else {
            state = 4;
        }
        goto Dispatch;
        
    StateIOS13: {
        SEL connScenesSel = sel_registerName("connectedScenes");
        NSSet *scenes = ((id(*)(id, SEL))objc_msgSend)(sharedApp, connScenesSel);
        NSArray *allScenes = [scenes allObjects];
        int i = 0;
        
        while (i < allScenes.count) {
            UIScene *scene = allScenes[i];
            Class winSceneCls = objc_getClass("UIWindowScene");
            if ([scene isKindOfClass:winSceneCls]) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    NSArray *wins = ws.windows;
                    for (UIWindow *w in wins) {
                        if (w.isKeyWindow) {
                            foundWindow = w;
                            state = 6;
                            goto Dispatch;
                        }
                    }
                }
            }
            i++;
        }
        state = 4;
        goto Dispatch;
    }
        
    StateSceneLoop:
        state = 4; 
        goto Dispatch;
        
    StateWinLoop:
        state = 6;
        goto Dispatch;
        
    StateLegacy: {
        SEL winsSel = sel_registerName("windows");
        NSArray *appWindows = ((id(*)(id, SEL))objc_msgSend)(sharedApp, winsSel);
        for (UIWindow *window in appWindows) {
            if (window.isKeyWindow) {
                foundWindow = window;
                state = 6;
                goto Dispatch;
            }
        }
        state = 5;
        goto Dispatch;
    }
        
    StateLegacyLoop: {
        SEL winsSel = sel_registerName("windows");
        NSArray *appWindows = ((id(*)(id, SEL))objc_msgSend)(sharedApp, winsSel);
        if (!foundWindow) {
            foundWindow = appWindows.firstObject;
        }
        state = 6;
        goto Dispatch;
    }
        
    StateFinal:
        state = 7;
        goto Dispatch;
        
    StateEnd:
        resultVC = foundWindow.rootViewController;
        while (resultVC.presentedViewController) {
            resultVC = resultVC.presentedViewController;
        }
    };
    
    finderBlock();
    return resultVC;
}

#pragma mark - MBProgressHUD Helpers

- (void)showHUDWithMessage:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [self getTopViewController];
        if (!topVC) return;
        
        if (!self.hud) {
            self.hud = [[MBProgressHUD alloc] initWithView:topVC.view];
            self.hud.backgroundView.style = MBProgressHUDBackgroundStyleSolidColor;
            self.hud.backgroundView.color = [UIColor colorWithWhite:0.0f alpha:0.4f];
            self.hud.label.textColor = [UIColor whiteColor];
            [topVC.view addSubview:self.hud];
        } else {
            [topVC.view bringSubviewToFront:self.hud];
        }
        
        self.hud.label.text = message;
        [self.hud showAnimated:YES];
    });
}

- (void)hideHUD {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.hud) {
            [self.hud hideAnimated:YES];
        }
    });
}

#pragma mark - FTNotificationIndicator Status System

- (void)showNotificationWithTitle:(NSString *)title message:(NSString *)message type:(int)type {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImage *statusIcon = nil;
        
        if (@available(iOS 13.0, *)) {
            if (type == 1) {
                statusIcon = [UIImage systemImageNamed:@"checkmark.circle"];
            } else if (type == 2) { 
                statusIcon = [UIImage systemImageNamed:@"xmark.circle"];
            } else if (type == 3) { 
                statusIcon = [UIImage systemImageNamed:@"exclamationmark.triangle"];
            } else { 
                statusIcon = [UIImage systemImageNamed:@"info.circle"];
            }
            statusIcon = [statusIcon imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        }
        
        [FTNotificationIndicator setNotificationIndicatorStyle:UIBlurEffectStyleDark];
        [FTNotificationIndicator showNotificationWithImage:statusIcon
                                                      title:title
                                                    message:message];
    });
}

- (void)forceExitApp:(NSString *)reason {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self hideHUD];
        
        [self showNotificationWithTitle:@"ระบบขัดข้อง" message:reason type:2];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            volatile int a = 10;
            volatile int b = 0;
            if (a > 5) exit(0);
            int c = a / b;
            (void)c;
        });
    });
}

- (void)startProcess {
    [self showHUDWithMessage:@"กำลังเชื่อมต่อระบบ..."];
    
    char u[] = {'?', 'a', 'c', 't', 'i', 'o', 'n', '=', 'i', 'n', 'i', 't', '&', 't', 'o', 'k', 'e', 'n', '=', 0};
    NSString *params = [NSString stringWithUTF8String:u];
    
    NSString *base = kBaseAPIURL;
    NSString *tk = kPackageToken;
    SEL fmtSel = sel_registerName("stringWithFormat:");
    NSString *fullURL = ((id(*)(id, SEL, id, ...))objc_msgSend)(objc_getClass("NSString"), fmtSel, @"%@%@%@", base, params, tk);
    
    char s_p[] = {'p','r','o','c','e','s','s','W','i','t','h','U','R','L',':', 0};
    SEL selector = sel_registerName(s_p);
    
    if ([self respondsToSelector:selector]) {
        [self vm_exec_selector:selector target:self object:fullURL];
    }
}

- (void)processWithURL:(NSString *)urlString {
    Class urlCls = objc_getClass("NSURL");
    SEL urlSel = sel_registerName("URLWithString:");
    id url = ((id(*)(id, SEL, id))objc_msgSend)(urlCls, urlSel, urlString);
    
    Class sessionCls = objc_getClass("NSURLSession");
    SEL sharedSel = sel_registerName("sharedSession");
    id session = ((id(*)(id, SEL))objc_msgSend)(sessionCls, sharedSel);
    
    SEL dataTaskSel = sel_registerName("dataTaskWithURL:completionHandler:");
    
    id task = ((id(*)(id, SEL, id, void (^)(NSData*, NSURLResponse*, NSError*)))objc_msgSend)(session, dataTaskSel, url, ^(NSData *data, NSURLResponse *response, NSError *error) {
        
        volatile int state = 0;
        NSDictionary *json = nil;
        void *branchTable[] = { &&L_CHECK_ERR, &&L_PARSE_JSON, &&L_CHECK_FORCE, &&L_CHECK_STATUS, &&L_ERR_DATA, &&L_EXIT };
        
    Branching:
        if (state < 0 || state > 5) state = 5;
        goto *branchTable[state];
        
    L_CHECK_ERR:
        if (error) {
            SEL forceSel = sel_registerName("forceExitApp:");
            ((void(*)(id, SEL, id))objc_msgSend)(self, forceSel, @"ไม่สามารถเชื่อมต่อกับเซิร์ฟเวอร์ได้");
            state = 5;
        } else {
            state = 1;
        }
        goto Branching;
        
    L_PARSE_JSON:
        if (data) {
            Class jsonCls = objc_getClass("NSJSONSerialization");
            SEL jsonSel = sel_registerName("JSONObjectWithData:options:error:");
            json = ((id(*)(id, SEL, id, NSInteger, id))objc_msgSend)(jsonCls, jsonSel, data, 0, nil);
            state = (json) ? 2 : 4;
        } else {
            state = 4;
        }
        goto Branching;
        
    L_CHECK_FORCE: {
        BOOL force = NO;
        if (json[@"force_exit"]) force = [json[@"force_exit"] boolValue];
        
        if (force) {
            SEL forceSel = sel_registerName("forceExitApp:");
            id msg = json[@"message"] ?: @"ไม่พบ Token ในระบบ";
            ((void(*)(id, SEL, id))objc_msgSend)(self, forceSel, msg);
            state = 5;
        } else {
            state = 3;
        }
        goto Branching;
    }
        
    L_CHECK_STATUS: {
        BOOL st = NO;
        if (json[@"status"]) st = [json[@"status"] boolValue];
        
        if (st) {
            SEL setCSel = sel_registerName("setContactLink:");
            ((void(*)(id, SEL, id))objc_msgSend)(self, setCSel, json[@"contact"]);
            
            SEL setMSel = sel_registerName("setIsMaintenance:");
            BOOL maint = [json[@"maintenance"] boolValue];
            ((void(*)(id, SEL, BOOL))objc_msgSend)(self, setMSel, maint);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideHUD];
                SEL succSel = sel_registerName("handleInitSuccess");
                ((void(*)(id, SEL))objc_msgSend)(self, succSel);
            });
        } else {
            SEL forceSel = sel_registerName("forceExitApp:");
            id msg = json[@"message"] ?: @"เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ";
            ((void(*)(id, SEL, id))objc_msgSend)(self, forceSel, msg);
        }
        state = 5;
        goto Branching;
    }
        
    L_ERR_DATA:
        {
            SEL forceSel = sel_registerName("forceExitApp:");
            ((void(*)(id, SEL, id))objc_msgSend)(self, forceSel, @"ข้อมูลเซิร์ฟเวอร์ไม่ถูกต้อง");
            state = 5;
        }
        goto Branching;
        
    L_EXIT:
        return;
    });
    
    SEL resumeSel = sel_registerName("resume");
    ((void(*)(id, SEL))objc_msgSend)(task, resumeSel);
}

- (void)handleInitSuccess {
    int index = 0;
    
    char k_key[] = {'s','a','v','e','d','_','l','i','c','e','n','s','e','_','k','e','y',0};
    NSString *savedKeyName = [NSString stringWithUTF8String:k_key];
    
    if (self.isMaintenance) {
        index = 0;
    } else {
        Class userDefCls = objc_getClass("NSUserDefaults");
        SEL stdSel = sel_registerName("standardUserDefaults");
        id userDef = ((id(*)(id, SEL))objc_msgSend)(userDefCls, stdSel);
        SEL objSel = sel_registerName("objectForKey:");
        NSString *savedKey = ((id(*)(id, SEL, id))objc_msgSend)(userDef, objSel, savedKeyName);
        index = (savedKey) ? 1 : 2;
    }
    
    typedef void (^ProcessBlock)(void);
    ProcessBlock b0 = ^{ [self showMaintenanceAlert]; };
    ProcessBlock b1 = ^{
        Class userDefCls = objc_getClass("NSUserDefaults");
        SEL stdSel = sel_registerName("standardUserDefaults");
        id userDef = ((id(*)(id, SEL))objc_msgSend)(userDefCls, stdSel);
        SEL objSel = sel_registerName("objectForKey:");
        NSString *k = ((id(*)(id, SEL, id))objc_msgSend)(userDef, objSel, savedKeyName);
        
        SEL checkSel = sel_registerName("checkKey:isAuto:");
        ((void(*)(id, SEL, id, BOOL))objc_msgSend)(self, checkSel, k, YES);
    };
    ProcessBlock b2 = ^{ [self showKeyAlert]; };
    
    ProcessBlock blocks[4];
    blocks[0] = b0;
    blocks[1] = b1;
    blocks[2] = b2;
    blocks[3] = b2;
    
    volatile int target_idx = index & 3;
    blocks[target_idx]();
}

- (void)showMaintenanceAlert {
    [self showNotificationWithTitle:@"แจ้งเตือน" message:@"ขณะนี้ระบบกำลังอยู่ในระหว่างการบำรุงรักษา" type:3];
    
    SEL getTopSel = sel_registerName("getTopViewController");
    UIViewController *rootVC = ((id(*)(id, SEL))objc_msgSend)(self, getTopSel);
    if (!rootVC) return;
    
    Class alertCls = objc_getClass("UIAlertController");
    SEL alertSel = sel_registerName("alertControllerWithTitle:message:preferredStyle:");
    id alert = ((id(*)(id, SEL, id, id, NSInteger))objc_msgSend)(alertCls, alertSel, @"ระบบปิดบำรุงรักษา", @"ขณะนี้ระบบกำลังอยู่ในระหว่างการบำรุงรักษา", 1);
    
    Class actionCls = objc_getClass("UIAlertAction");
    SEL actionSel = sel_registerName("actionWithTitle:style:handler:");
    SEL addActSel = sel_registerName("addAction:");
    
    if (self.contactLink.length > 0) {
        id act = ((id(*)(id, SEL, id, NSInteger, void (^)(id)))objc_msgSend)(actionCls, actionSel, @"ติดต่อทีมงาน", 2, ^(id action) {
            Class appCls = objc_getClass("UIApplication");
            SEL sharedSel = sel_registerName("sharedApplication");
            id app = ((id(*)(id, SEL))objc_msgSend)(appCls, sharedSel);
            SEL openSel = sel_registerName("openURL:options:completionHandler:");
            NSURL *u = [NSURL URLWithString:self.contactLink];
            ((void(*)(id, SEL, id, id, id))objc_msgSend)(app, openSel, u, @{}, nil);
            exit(0);
        });
        ((void(*)(id, SEL, id))objc_msgSend)(alert, addActSel, act);
    } else {
        id act = ((id(*)(id, SEL, id, NSInteger, void (^)(id)))objc_msgSend)(actionCls, actionSel, @"ออกจากแอป", 2, ^(id action) { exit(0); });
        ((void(*)(id, SEL, id))objc_msgSend)(alert, addActSel, act);
    }
    
    SEL presentSel = sel_registerName("presentViewController:animated:completion:");
    ((void(*)(id, SEL, id, BOOL, id))objc_msgSend)(rootVC, presentSel, alert, YES, nil);
}

- (void)showKeyAlert {
    SEL getTopSel = sel_registerName("getTopViewController");
    UIViewController *rootVC = ((id(*)(id, SEL))objc_msgSend)(self, getTopSel);
    if (!rootVC) return;
    
    Class alertCls = objc_getClass("UIAlertController");
    SEL alertSel = sel_registerName("alertControllerWithTitle:message:preferredStyle:");
    id alert = ((id(*)(id, SEL, id, id, NSInteger))objc_msgSend)(alertCls, alertSel, @"เข้าสู่ระบบ", @"กรอกคีย์เพื่อเข้าใช้งาน", 1);
    
    SEL configSel = sel_registerName("configureTextFieldForAlert:");
    ((void(*)(id, SEL, id))objc_msgSend)(self, configSel, alert);
    
    Class actionCls = objc_getClass("UIAlertAction");
    SEL actionSel = sel_registerName("actionWithTitle:style:handler:");
    SEL addActSel = sel_registerName("addAction:");
    
    if (self.contactLink.length > 0) {
        id act = ((id(*)(id, SEL, id, NSInteger, void (^)(id)))objc_msgSend)(actionCls, actionSel, @"ติดต่อสอบถาม", 2, ^(id action) {
            Class appCls = objc_getClass("UIApplication");
            SEL sharedSel = sel_registerName("sharedApplication");
            id app = ((id(*)(id, SEL))objc_msgSend)(appCls, sharedSel);
            SEL openSel = sel_registerName("openURL:options:completionHandler:");
            NSURL *u = [NSURL URLWithString:self.contactLink];
            ((void(*)(id, SEL, id, id, id))objc_msgSend)(app, openSel, u, @{}, nil);
            [self showKeyAlert];
        });
        ((void(*)(id, SEL, id))objc_msgSend)(alert, addActSel, act);
    }
    
    id actLogin = ((id(*)(id, SEL, id, NSInteger, void (^)(id)))objc_msgSend)(actionCls, actionSel, @"เข้าสู่ระบบ", 0, ^(id action) {
        UITextField *tf = ((NSArray *)((id(*)(id, SEL))objc_msgSend)(alert, sel_registerName("textFields"))).firstObject;
        if (tf.text.length > 0) {
            SEL checkSel = sel_registerName("checkKey:isAuto:");
            ((void(*)(id, SEL, id, BOOL))objc_msgSend)(self, checkSel, tf.text, NO);
        } else {
            [self showNotificationWithTitle:@"แจ้งเตือน" message:@"กรุณากรอกคีย์ให้อีกครั้ง" type:3];
            [self showKeyAlert];
        }
    });
    ((void(*)(id, SEL, id))objc_msgSend)(alert, addActSel, actLogin);
    
    SEL presentSel = sel_registerName("presentViewController:animated:completion:");
    ((void(*)(id, SEL, id, BOOL, id))objc_msgSend)(rootVC, presentSel, alert, YES, nil);
}

- (void)configureTextFieldForAlert:(UIAlertController *)alert {
    SEL addTF = sel_registerName("addTextFieldWithConfigurationHandler:");
    ((void(*)(id, SEL, void (^)(UITextField *)))objc_msgSend)(alert, addTF, ^(UITextField *textField) {
        textField.placeholder = @"กรอกคีย์ของคุณ";
        textField.textAlignment = NSTextAlignmentCenter;
    });
}

- (void)checkKey:(NSString *)key isAuto:(BOOL)isAuto {
    [self showHUDWithMessage:@"กำลังตรวจสอบคีย์..."];
    
    Class deviceCls = objc_getClass("UIDevice");
    SEL curDevSel = sel_registerName("currentDevice");
    id dev = ((id(*)(id, SEL))objc_msgSend)(deviceCls, curDevSel);
    SEL idVendorSel = sel_registerName("identifierForVendor");
    NSUUID *uuidObj = ((id(*)(id, SEL))objc_msgSend)(dev, idVendorSel);
    NSString *uuid = uuidObj.UUIDString;
    
    char fmt[] = {'%','@','?','a','c','t','i','o','n','=','c','h','e','c','k','&','t','o','k','e','n','=','%','@','&','k','e','y','=','%','@','&','u','u','i','d','=','%','@',0};
    NSString *fmtStr = [NSString stringWithUTF8String:fmt];
    
    SEL strFmtSel = sel_registerName("stringWithFormat:");
    NSString *urlString = ((id(*)(id, SEL, id, ...))objc_msgSend)(objc_getClass("NSString"), strFmtSel, fmtStr, kBaseAPIURL, kPackageToken, key, uuid);
    
    SEL execSel = sel_registerName("executeNetworkCheck:key:autoMode:");
    ((void(*)(id, SEL, id, id, BOOL))objc_msgSend)(self, execSel, urlString, key, isAuto);
}

- (void)executeNetworkCheck:(NSString *)urlStr key:(NSString *)key autoMode:(BOOL)isAuto {
    NSURL *url = [NSURL URLWithString:urlStr];
    
    Class sessionCls = objc_getClass("NSURLSession");
    SEL sharedSel = sel_registerName("sharedSession");
    id session = ((id(*)(id, SEL))objc_msgSend)(sessionCls, sharedSel);
    SEL dataTaskSel = sel_registerName("dataTaskWithURL:completionHandler:");
    
    id task = ((id(*)(id, SEL, id, void (^)(NSData*, NSURLResponse*, NSError*)))objc_msgSend)(session, dataTaskSel, url, ^(NSData *data, NSURLResponse *response, NSError *error) {
        
        volatile int currentState = 100;
        NSDictionary *json = nil;
        volatile BOOL loop = YES;
        
        void *labels[] = { &&State100, &&State200, &&State300, &&State400, &&State401, &&State402, &&State500, &&State501, &&ExitLoop };
        
        int labelIndex = 0;
        
    DispatchLoop:
        if (!loop) goto ExitLoop;
        
        if (currentState == 100) labelIndex = 0;
        else if (currentState == 200) labelIndex = 1;
        else if (currentState == 300) labelIndex = 2;
        else if (currentState == 400) labelIndex = 3;
        else if (currentState == 401) labelIndex = 4;
        else if (currentState == 402) labelIndex = 5;
        else if (currentState == 500) labelIndex = 6;
        else if (currentState == 501) labelIndex = 7;
        else labelIndex = 8;
        
        goto *labels[labelIndex];
        
    State100:
        if (error) currentState = 500;
        else currentState = 200;
        goto DispatchLoop;
        
    State200:
        if (!data) { currentState = 501; goto DispatchLoop; }
        {
            Class jsonCls = objc_getClass("NSJSONSerialization");
            SEL jsonSel = sel_registerName("JSONObjectWithData:options:error:");
            json = ((id(*)(id, SEL, id, NSInteger, id))objc_msgSend)(jsonCls, jsonSel, data, 0, nil);
        }
        if (!json) currentState = 501;
        else currentState = 300;
        goto DispatchLoop;
        
    State300:
        if ([json[@"force_exit"] boolValue]) {
            [self hideHUD];
            SEL forceSel = sel_registerName("forceExitApp:");
            ((void(*)(id, SEL, id))objc_msgSend)(self, forceSel, json[@"message"] ?: @"Token package error");
            loop = NO;
        } else {
            currentState = 400;
        }
        goto DispatchLoop;
        
    State400:
        if (json[@"contact"]) {
            self.contactLink = json[@"contact"];
        }
        if ([json[@"status"] boolValue]) currentState = 401;
        else currentState = 402;
        goto DispatchLoop;
        
    State401: {
        // บันทึก Key ลงใน NSUserDefaults เมื่อการยืนยันตัวตนสำเร็จ
        char k_sv[] = {'s','a','v','e','d','_','l','i','c','e','n','s','e','_','k','e','y',0};
        Class udCls = objc_getClass("NSUserDefaults");
        id ud = ((id(*)(id, SEL))objc_msgSend)(udCls, sel_registerName("standardUserDefaults"));
        SEL setObj = sel_registerName("setObject:forKey:");
        ((void(*)(id, SEL, id, id))objc_msgSend)(ud, setObj, key, [NSString stringWithUTF8String:k_sv]);
        ((void(*)(id, SEL))objc_msgSend)(ud, sel_registerName("synchronize"));
        
        NSString *rawExpiry = json[@"expiry"] ?: @"-";
        NSString *formattedLocalExpiry = rawExpiry;
        NSString *remainingTimeString = @"";
        
        // แปลงเวลา UTC จาก Server เป็นเวลาตาม Timezone เครื่องผู้ใช้โดยอัตโนมัติ
        if (rawExpiry.length > 0 && ![rawExpiry isEqualToString:@"-"]) {
            NSDateFormatter *utcFormatter = [[NSDateFormatter alloc] init];
            [utcFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
            [utcFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
            [utcFormatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
            
            NSDate *expireDate = [utcFormatter dateFromString:rawExpiry];
            if (expireDate) {
                NSDateFormatter *localFormatter = [[NSDateFormatter alloc] init];
                [localFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
                [localFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                [localFormatter setTimeZone:[NSTimeZone systemTimeZone]]; // ใช้ Timezone ตามตำแหน่งประเทศของผู้ใช้
                formattedLocalExpiry = [localFormatter stringFromDate:expireDate];
                
                // คำนวณความต่างเวลาแบบ วัน ชั่วโมง นาที วินาที
                NSDate *nowDate = [NSDate date];
                NSCalendar *calendar = [NSCalendar currentCalendar];
                NSCalendarUnit units = NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
                NSDateComponents *components = [calendar components:unitsfromDate:nowDate toDate:expireDate options:0];
                
                NSInteger days = components.day > 0 ? components.day : 0;
                NSInteger hours = components.hour > 0 ? components.hour : 0;
                NSInteger minutes = components.minute > 0 ? components.minute : 0;
                NSInteger seconds = components.second > 0 ? components.second : 0;
                
                remainingTimeString = [NSString stringWithFormat:@" (เหลืออีก %ld วัน %ld ชั่วโมง %ld นาที %ld วินาที)", (long)days, (long)hours, (long)minutes, (long)seconds];
            }
        }
        
        NSString *info = [NSString stringWithFormat:@"วันหมดอายุ: %@%@", formattedLocalExpiry, remainingTimeString];
        
        [self hideHUD];
        [self showNotificationWithTitle:@"เข้าสู่ระบบสำเร็จ" message:info type:1];
        loop = NO;
        goto DispatchLoop;
    }
        
    State402:
        {
            [self hideHUD];
            NSString *errMsg = json[@"message"] ?: @"เข้าสู่ระบบไม่สำเร็จ";
            SEL invKeySel = sel_registerName("handleInvalidKey:message:isAuto:");
            ((void(*)(id, SEL, id, id, BOOL))objc_msgSend)(self, invKeySel, key, errMsg, isAuto);
        }
        loop = NO;
        goto DispatchLoop;
        
    State500:
        {
            [self hideHUD];
            [self showNotificationWithTitle:@"เกิดข้อผิดพลาดในการเชื่อมต่อ" message:error.localizedDescription type:2];
        }
        loop = NO;
        goto DispatchLoop;
        
    State501:
        {
            [self hideHUD];
            [self showNotificationWithTitle:@"Server Error" message:@"ข้อมูลจากเซิร์ฟเวอร์ไม่ถูกต้อง" type:2];
        }
        loop = NO;
        goto DispatchLoop;
        
    ExitLoop:
        return;
        
    });
    SEL resumeSel = sel_registerName("resume");
    ((void(*)(id, SEL))objc_msgSend)(task, resumeSel);
}

- (void)handleInvalidKey:(NSString *)key message:(NSString *)msg isAuto:(BOOL)isAuto {
    char sel_c[] = {'r','e','m','o','v','e','O','b','j','e','c','t','F','o','r','K','e','y',':',0};
    SEL removeSel = NSSelectorFromString([NSString stringWithUTF8String:sel_c]);
    Class udCls = objc_getClass("NSUserDefaults");
    SEL stdSel = sel_registerName("standardUserDefaults");
    
    if ([udCls instancesRespondToSelector:removeSel]) {
        char k_sv[] = {'s','a','v','e','d','_','l','i','c','e','n','s','e','_','k','e','y',0};
        NSString *k = [NSString stringWithUTF8String:k_sv];
        id ud = ((id(*)(id, SEL))objc_msgSend)(udCls, stdSel);
        
        ImpFuncType func = (ImpFuncType)objc_msgSend;
        void (*volatile indirect_call)(id, SEL, id) = func;
        indirect_call(ud, removeSel, k);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showNotificationWithTitle:@"เข้าสู่ระบบไม่สำเร็จ" message:msg type:2];
        
        if (isAuto) {
            SEL showKeySel = sel_registerName("showKeyAlert");
            ((void(*)(id, SEL))objc_msgSend)(self, showKeySel);
        } else {
            SEL showKeySel = sel_registerName("showKeyAlert");
            ((void(*)(id, SEL))objc_msgSend)(self, showKeySel);
        }
    });
}

@end
