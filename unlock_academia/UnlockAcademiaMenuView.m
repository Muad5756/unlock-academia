#import "UnlockAcademiaMenuView.h"
#import "BypassSettings.h"
#import "BypassHooks.h"

static UIButton *gFloatingButton = nil;
static UnlockAcademiaMenuView *gMenuView = nil;

@interface UnlockAcademiaMenuView ()

@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *balanceLabel;
@property (nonatomic, strong) UISwitch *drmSwitch;
@property (nonatomic, strong) UISwitch *purchaseSwitch;
@property (nonatomic, strong) UILabel *drmStatusLabel;
@property (nonatomic, strong) UILabel *purchaseStatusLabel;

@end

@implementation UnlockAcademiaMenuView

+ (UIWindow *)keyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            UIWindow *win = ((UIWindowScene *)scene).windows.firstObject;
            if (win.isKeyWindow) return win;
        }
    }
    return nil;
}

+ (void)addFloatingButton {
    if (gFloatingButton) return;
    
    UIWindow *win = [self keyWindow];
    if (!win) return;
    
    CGFloat sz = 56;
    CGFloat pad = 20;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(pad, 120, sz, sz);
    btn.backgroundColor = [UIColor colorWithRed:0.90 green:0.10 blue:0.20 alpha:0.95];
    btn.layer.cornerRadius = sz / 2;
    btn.clipsToBounds = YES;
    btn.tintColor = [UIColor whiteColor];
    btn.layer.borderWidth = 2.0;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    
    // Modern iOS shadow
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 4);
    btn.layer.shadowRadius = 8;
    btn.layer.shadowOpacity = 0.4;
    btn.layer.masksToBounds = NO;
    
    [btn setImage:[UIImage systemImageNamed:@"bolt.shield.fill"] forState:UIControlStateNormal];
    [btn setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightBold] forImageInState:UIControlStateNormal];
    
    btn.accessibilityLabel = @"Bypass Control Button";
    
    [btn addTarget:self action:@selector(floatingButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFloatingButtonPan:)];
    [btn addGestureRecognizer:pan];
    
    [win addSubview:btn];
    [win bringSubviewToFront:btn];
    gFloatingButton = btn;
    
    NSLog(@"[unlock_academia] Premium floating button added");
}

+ (void)floatingButtonTapped {
    if (gMenuView) {
        [self hide];
    } else {
        [self show];
    }
}

+ (void)handleFloatingButtonPan:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    UIView *parent = btn.superview;
    if (!parent) return;
    
    CGPoint pt = [pan translationInView:parent];
    CGPoint center = btn.center;
    center.x += pt.x;
    center.y += pt.y;
    
    // Bounds check
    CGFloat halfW = btn.frame.size.width / 2.0;
    CGFloat halfH = btn.frame.size.height / 2.0;
    center.x = MAX(halfW, MIN(parent.bounds.size.width - halfW, center.x));
    center.y = MAX(halfH, MIN(parent.bounds.size.height - halfH, center.y));
    
    btn.center = center;
    [pan setTranslation:CGPointZero inView:parent];
}

+ (void)show {
    if (gMenuView) return;
    
    UIWindow *win = [self keyWindow];
    if (!win) return;
    
    UnlockAcademiaMenuView *menu = [[UnlockAcademiaMenuView alloc] initWithFrame:CGRectMake(0, 0, 340, 460)];
    menu.center = CGPointMake(win.bounds.size.width / 2.0, win.bounds.size.height / 2.0);
    menu.alpha = 0.0;
    menu.transform = CGAffineTransformMakeScale(0.85, 0.85);
    
    [win addSubview:menu];
    [win bringSubviewToFront:menu];
    gMenuView = menu;
    
    [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        menu.alpha = 1.0;
        menu.transform = CGAffineTransformIdentity;
    } completion:nil];
}

+ (void)hide {
    if (!gMenuView) return;
    
    UnlockAcademiaMenuView *menu = gMenuView;
    gMenuView = nil;
    
    [UIView animateWithDuration:0.25 animations:^{
        menu.alpha = 0.0;
        menu.transform = CGAffineTransformMakeScale(0.85, 0.85);
    } completion:^(BOOL finished) {
        [menu removeFromSuperview];
    }];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 24.0;
        self.clipsToBounds = YES;
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
        
        // Shadow (on a container if clipping, but here we can just add shadow directly if we keep clipsToBounds=YES but add it to window or configure mask)
        // For simplicity under dynamic views:
        self.backgroundColor = [UIColor clearColor];
        
        // Add Glassmorphism blur
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        _blurView.frame = self.bounds;
        _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_blurView];
        
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    UIView *contentView = _blurView.contentView;
    
    // Drag gesture for the menu window
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleMenuPan:)];
    [self addGestureRecognizer:pan];
    
    // Header Title
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 240, 28)];
    _titleLabel.text = @"Academia Bypass Center";
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightBold];
    [contentView addSubview:_titleLabel];
    
    // Close Button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(self.frame.size.width - 50, 16, 36, 36);
    closeBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    closeBtn.layer.cornerRadius = 18;
    closeBtn.tintColor = [UIColor whiteColor];
    [closeBtn setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    [closeBtn setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:closeBtn];
    
    // Separator line
    UIView *sep1 = [[UIView alloc] initWithFrame:CGRectMake(20, 64, self.frame.size.width - 40, 1)];
    sep1.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    [contentView addSubview:sep1];
    
    // Wallet section header
    UILabel *walletSec = [[UILabel alloc] initWithFrame:CGRectMake(20, 78, 200, 20)];
    walletSec.text = @"المحفظة الرقمية";
    walletSec.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    walletSec.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    [contentView addSubview:walletSec];
    
    // Balance pill container
    UIView *balanceCard = [[UIView alloc] initWithFrame:CGRectMake(20, 106, self.frame.size.width - 40, 68)];
    balanceCard.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    balanceCard.layer.cornerRadius = 16;
    balanceCard.layer.borderWidth = 1;
    balanceCard.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    [contentView addSubview:balanceCard];
    
    UILabel *balTitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, 100, 18)];
    balTitle.text = @"الرصيد الحالي:";
    balTitle.textColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    balTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    [balanceCard addSubview:balTitle];
    
    _balanceLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 32, balanceCard.frame.size.width - 32, 28)];
    _balanceLabel.text = [BypassSettings formatBalance:[BypassSettings getWalletBalance]];
    _balanceLabel.textColor = [UIColor colorWithRed:0.20 green:0.80 blue:0.40 alpha:1.0]; // Bright green
    _balanceLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    [balanceCard addSubview:_balanceLabel];
    
    // Quick Wallet Operations
    UIButton *add1kBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    add1kBtn.frame = CGRectMake(20, 186, 140, 38);
    add1kBtn.backgroundColor = [UIColor colorWithRed:0.29 green:0.56 blue:0.89 alpha:0.2];
    add1kBtn.layer.cornerRadius = 12;
    add1kBtn.layer.borderWidth = 1;
    add1kBtn.layer.borderColor = [UIColor colorWithRed:0.29 green:0.56 blue:0.89 alpha:0.4].CGColor;
    add1kBtn.tintColor = [UIColor colorWithRed:0.35 green:0.65 blue:0.95 alpha:1.0];
    [add1kBtn setTitle:@"➕ ١٠٠٠ ر.س" forState:UIControlStateNormal];
    add1kBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [add1kBtn addTarget:self action:@selector(add1kTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:add1kBtn];
    
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(self.frame.size.width - 160, 186, 140, 38);
    resetBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    resetBtn.layer.cornerRadius = 12;
    resetBtn.layer.borderWidth = 1;
    resetBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    resetBtn.tintColor = [UIColor whiteColor];
    [resetBtn setTitle:@"🔄 تعيين ١٠ آلاف" forState:UIControlStateNormal];
    resetBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [resetBtn addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:resetBtn];
    
    // Separator line 2
    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(20, 240, self.frame.size.width - 40, 1)];
    sep2.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.1];
    [contentView addSubview:sep2];
    
    // Toggles header
    UILabel *togglesSec = [[UILabel alloc] initWithFrame:CGRectMake(20, 254, 200, 20)];
    togglesSec.text = @"أدوات التجاوز والتحكم";
    togglesSec.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    togglesSec.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    [contentView addSubview:togglesSec];
    
    // DRM Toggle Row
    UILabel *drmLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 288, 200, 20)];
    drmLabel.text = @"تجاوز حماية DRM والجيلبريك";
    drmLabel.textColor = [UIColor whiteColor];
    drmLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [contentView addSubview:drmLabel];
    
    _drmStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 308, 200, 16)];
    _drmStatusLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    [contentView addSubview:_drmStatusLabel];
    
    _drmSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(self.frame.size.width - 71, 290, 51, 31)];
    _drmSwitch.onTintColor = [UIColor colorWithRed:0.90 green:0.10 blue:0.20 alpha:0.95];
    [_drmSwitch setOn:[BypassSettings isDRMBypassActive] animated:NO];
    [_drmSwitch addTarget:self action:@selector(drmToggled:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:_drmSwitch];
    
    // Free Purchases Toggle Row
    UILabel *purLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 350, 200, 20)];
    purLabel.text = @"تفعيل الشراء المجاني";
    purLabel.textColor = [UIColor whiteColor];
    purLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [contentView addSubview:purLabel];
    
    _purchaseStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 370, 200, 16)];
    _purchaseStatusLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    [contentView addSubview:_purchaseStatusLabel];
    
    _purchaseSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(self.frame.size.width - 71, 352, 51, 31)];
    _purchaseSwitch.onTintColor = [UIColor colorWithRed:0.90 green:0.10 blue:0.20 alpha:0.95];
    [_purchaseSwitch setOn:[BypassSettings isFreePurchasesEnabled] animated:NO];
    [_purchaseSwitch addTarget:self action:@selector(purchaseToggled:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:_purchaseSwitch];
    
    // Bottom copyright label
    UILabel *copyLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 420, self.frame.size.width - 40, 20)];
    copyLabel.text = @"unlock_academia • v1.9.14 Educational Build";
    copyLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.35];
    copyLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightRegular];
    copyLabel.textAlignment = NSTextAlignmentCenter;
    [contentView addSubview:copyLabel];
    
    [self updateStatusLabels];
}

- (void)handleMenuPan:(UIPanGestureRecognizer *)pan {
    UIView *parent = self.superview;
    if (!parent) return;
    
    CGPoint pt = [pan translationInView:parent];
    CGPoint center = self.center;
    center.x += pt.x;
    center.y += pt.y;
    
    // Keep it on screen
    CGFloat halfW = self.frame.size.width / 2.0;
    CGFloat halfH = self.frame.size.height / 2.0;
    center.x = MAX(halfW, MIN(parent.bounds.size.width - halfW, center.x));
    center.y = MAX(halfH, MIN(parent.bounds.size.height - halfH, center.y));
    
    self.center = center;
    [pan setTranslation:CGPointZero inView:parent];
}

- (void)updateStatusLabels {
    if ([BypassSettings isDRMBypassActive]) {
        _drmStatusLabel.text = @"✅ التجاوز نشط (الحماية معطلة)";
        _drmStatusLabel.textColor = [UIColor colorWithRed:0.25 green:0.75 blue:0.45 alpha:1.0];
    } else {
        _drmStatusLabel.text = @"❌ التجاوز غير نشط (الحماية تعمل)";
        _drmStatusLabel.textColor = [UIColor colorWithRed:0.90 green:0.30 blue:0.30 alpha:1.0];
    }
    
    if ([BypassSettings isFreePurchasesEnabled]) {
        _purchaseStatusLabel.text = @"✅ الشراء المجاني نشط";
        _purchaseStatusLabel.textColor = [UIColor colorWithRed:0.25 green:0.75 blue:0.45 alpha:1.0];
    } else {
        _purchaseStatusLabel.text = @"❌ الشراء المجاني معطل";
        _purchaseStatusLabel.textColor = [UIColor colorWithRed:0.90 green:0.30 blue:0.30 alpha:1.0];
    }
}

#pragma mark - Actions

- (void)closeTapped {
    [UnlockAcademiaMenuView hide];
}

- (void)add1kTapped {
    [BypassSettings addWalletBalance:1000.0];
    _balanceLabel.text = [BypassSettings formatBalance:[BypassSettings getWalletBalance]];
}

- (void)resetTapped {
    [BypassSettings setWalletBalance:10000.0];
    _balanceLabel.text = [BypassSettings formatBalance:[BypassSettings getWalletBalance]];
}

- (void)drmToggled:(UISwitch *)sender {
    [BypassSettings setDRMBypassActive:sender.isOn];
    [self updateStatusLabels];
    
    // If bypass is re-enabled, scan textfields again to apply bypass immediately
    if (sender.isOn) {
        [BypassHooks scanAndDisableSecureTextFields];
    }
}

- (void)purchaseToggled:(UISwitch *)sender {
    [BypassSettings setFreePurchasesEnabled:sender.isOn];
    [self updateStatusLabels];
}

@end
