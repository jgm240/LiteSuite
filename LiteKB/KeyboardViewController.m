// LiteKB: a deliberately small keyboard. No autocorrect, prediction, images, haptics or
// Auto Layout: plain opaque buttons positioned by frame.
#import <UIKit/UIKit.h>

// Key style set from LiteBoard > gear > Keyboard. Plain plist so the extension needs no
// app group; it is read once each time the keyboard appears.
#define LK_CONFIG_PATH @"/var/mobile/Library/Preferences/com.liteboard.litekb.plist"
static const CGFloat kDefRadius = 5, kDefScale = 1.0, kDefFont = 22;

@interface LKKey : UIButton
@property (nonatomic, strong) UIColor *normalColor, *pressedColor;
@end

@implementation LKKey
- (void)setHighlighted:(BOOL)h {
	[super setHighlighted:h];
	self.backgroundColor = h ? self.pressedColor : self.normalColor;
}
@end

@interface KeyboardViewController : UIInputViewController
@end

// Letter page, number page, symbol page: three rows each (the bottom row is fixed).
static NSString *const kPages[3][3] = {
	{ @"qwertyuiop", @"asdfghjkl", @"zxcvbnm" },
	{ @"1234567890", @"-/:;()$&@\"", @".,?!'" },
	{ @"[]{}#%^*+=", @"_\\|~<>€£¥•", @".,?!'" },
};

// Long-press alternates, keyed by the lowercase base character.
static NSDictionary<NSString *, NSString *> *Accents(void) {
	static NSDictionary *d;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		d = @{
			@"a": @"àáâäæãåā", @"c": @"çćč", @"d": @"ð", @"e": @"èéêëēėę", @"i": @"îïíīįì",
			@"l": @"ł", @"n": @"ñń", @"o": @"ôöòóœøōõ", @"s": @"ßśš", @"t": @"þ",
			@"u": @"ûüùúū", @"y": @"ÿý", @"z": @"žźż",
			@"-": @"–—•", @".": @"…", @"?": @"¿", @"!": @"¡", @"'": @"‘’", @"\"": @"“”«»",
			@"$": @"€£¥¢", @"0": @"°", @"%": @"‰",
		};
	});
	return d;
}

@implementation KeyboardViewController {
	NSArray<NSMutableArray<LKKey *> *> *_rows;   // 3 rows of character keys
	LKKey *_shift, *_del, *_mode, *_globe, *_space, *_ret;
	NSLayoutConstraint *_height;
	NSTimer *_delayTimer, *_repeatTimer;
	NSInteger _page;           // 0 letters, 1 numbers, 2 symbols
	NSInteger _shiftState;     // 0 off, 1 once, 2 caps lock
	NSTimeInterval _lastShiftTap;

	CGFloat _radius, _scale, _font;   // from the config plist
	UIView *_popup;                   // long-press alternates
	NSArray<UILabel *> *_popupLabels;
	NSInteger _popupIndex;
	NSString *_popupBase;
	CGFloat _spaceDragX, _spaceMoved;
}

#pragma mark - Setup

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.multipleTouchEnabled = YES;
	[self loadConfig];

	NSUInteger caps[3] = { 10, 10, 7 };
	NSMutableArray *rows = [NSMutableArray array];
	for (int r = 0; r < 3; r++) {
		NSMutableArray *row = [NSMutableArray array];
		for (NSUInteger i = 0; i < caps[r]; i++) {
			LKKey *k = [self key:@"" action:@selector(charDown:)];
			UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
			lp.minimumPressDuration = 0.35;
			[k addGestureRecognizer:lp];
			[row addObject:k];
		}
		[rows addObject:row];
	}
	_rows = rows;
	_shift = [self key:@"" action:@selector(shiftDown:)];
	_del   = [self key:@"⌫" action:@selector(delDown:)];
	[_del addTarget:self action:@selector(delUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
	_mode  = [self key:@"123" action:@selector(modeDown:)];
	_globe = [self key:@"🌐" action:@selector(globeDown:)];
	_ret   = [self key:@"return" action:@selector(retDown:)];

	// Space inserts on touch-up so a horizontal swipe can move the cursor instead.
	_space = [self key:@"" action:nil];
	[_space addTarget:self action:@selector(spaceUp:) forControlEvents:UIControlEventTouchUpInside];
	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(spacePan:)];
	[_space addGestureRecognizer:pan];

	_height = [NSLayoutConstraint constraintWithItem:self.view attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:264];
	_height.priority = 999;
	[self.view addConstraint:_height];

	[self refresh];
}

- (LKKey *)key:(NSString *)title action:(SEL)action {
	LKKey *k = [LKKey buttonWithType:UIButtonTypeCustom];
	[k setTitle:title forState:UIControlStateNormal];
	if (action) [k addTarget:self action:action forControlEvents:UIControlEventTouchDown];
	[self.view addSubview:k];
	return k;
}

- (void)loadConfig {
	NSDictionary *c = [NSDictionary dictionaryWithContentsOfFile:LK_CONFIG_PATH];
	CGFloat (^num)(NSString *, CGFloat, CGFloat, CGFloat) = ^CGFloat(NSString *key, CGFloat def, CGFloat lo, CGFloat hi) {
		id v = c[key];
		CGFloat x = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : def;
		return MIN(hi, MAX(lo, x));
	};
	_radius = num(@"cornerRadius", kDefRadius, 0, 24);
	_scale  = num(@"keySize", kDefScale, 0.6, 1.5);
	_font   = num(@"fontSize", kDefFont, 10, 40);
}

#pragma mark - Layout

- (void)viewWillLayoutSubviews {
	CGFloat w = self.view.bounds.size.width;
	BOOL pad = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad;
	CGFloat base = pad ? (w > 800 ? 352 : 264) : (w > 500 ? 162 : 216);
	_height.constant = round(base * _scale);
	[super viewWillLayoutSubviews];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
	CGFloat edge = 4, gap = 6, top = 8;
	CGFloat kh = (H - top - 4 - 3 * gap) / 4;
	CGFloat u = (W - 2 * edge - 9 * gap) / 10;
	CGFloat wide = 1.5 * u;

	for (int r = 0; r < 3; r++) {
		NSString *chars = kPages[_page][r];
		NSUInteger n = chars.length;
		CGFloat y = top + r * (kh + gap);
		CGFloat total = n * u + (n - 1) * gap;
		CGFloat x0 = (W - total) / 2;
		NSArray<LKKey *> *row = _rows[r];
		for (NSUInteger i = 0; i < row.count; i++) {
			LKKey *k = row[i];
			k.hidden = i >= n;
			k.frame = CGRectMake(x0 + i * (u + gap), y, u, kh);
		}
	}
	CGFloat y3 = top + 2 * (kh + gap);
	_shift.frame = CGRectMake(edge, y3, wide, kh);
	_del.frame = CGRectMake(W - edge - wide, y3, wide, kh);

	CGFloat yb = top + 3 * (kh + gap);
	CGFloat retW = 2.2 * u;
	_mode.frame = CGRectMake(edge, yb, wide, kh);
	CGFloat x = edge + wide + gap;
	_globe.hidden = NO; // needsInputModeSwitchKey is iOS 11+; always show it on iOS 10
	_globe.frame = CGRectMake(x, yb, 1.2 * u, kh);
	x += 1.2 * u + gap;
	_ret.frame = CGRectMake(W - edge - retW, yb, retW, kh);
	_space.frame = CGRectMake(x, yb, CGRectGetMinX(_ret.frame) - gap - x, kh);
}

#pragma mark - Appearance / state

- (void)refresh {
	BOOL dark = self.textDocumentProxy.keyboardAppearance == UIKeyboardAppearanceDark;
	UIColor *bg      = dark ? [UIColor colorWithWhite:0.10 alpha:1] : [UIColor colorWithRed:0.82 green:0.84 blue:0.86 alpha:1];
	UIColor *keyBg   = dark ? [UIColor colorWithWhite:0.36 alpha:1] : [UIColor whiteColor];
	UIColor *specBg  = dark ? [UIColor colorWithWhite:0.22 alpha:1] : [UIColor colorWithRed:0.67 green:0.70 blue:0.73 alpha:1];
	UIColor *pressed = dark ? [UIColor colorWithWhite:0.50 alpha:1] : [UIColor colorWithWhite:0.75 alpha:1];
	UIColor *text    = dark ? [UIColor whiteColor] : [UIColor blackColor];
	self.view.backgroundColor = bg;
	UIFont *charFont = [UIFont systemFontOfSize:_font];
	UIFont *specFont = [UIFont systemFontOfSize:MAX(10, round(_font * 0.75))];

	for (int r = 0; r < 3; r++) {
		NSString *chars = kPages[_page][r];
		NSArray<LKKey *> *row = _rows[r];
		for (NSUInteger i = 0; i < row.count; i++) {
			LKKey *k = row[i];
			if (i < chars.length) {
				NSString *s = [NSString stringWithFormat:@"%C", [chars characterAtIndex:i]];
				if (_page == 0 && _shiftState) s = s.uppercaseString;
				[k setTitle:s forState:UIControlStateNormal];
			}
			[self style:k bg:keyBg pressed:pressed text:text font:charFont];
		}
	}
	NSString *shiftTitle = _page == 0 ? (_shiftState == 2 ? @"⇪" : @"⇧") : (_page == 1 ? @"#+=" : @"123");
	[_shift setTitle:shiftTitle forState:UIControlStateNormal];
	[_mode setTitle:_page == 0 ? @"123" : @"ABC" forState:UIControlStateNormal];
	BOOL shiftOn = _page == 0 && _shiftState;
	for (LKKey *k in @[_shift, _del, _mode, _globe, _ret]) [self style:k bg:specBg pressed:pressed text:text font:specFont];
	if (shiftOn) [self style:_shift bg:keyBg pressed:pressed text:text font:specFont];
	[self style:_space bg:keyBg pressed:pressed text:text font:specFont];
	[self.view setNeedsLayout];
}

- (void)style:(LKKey *)k bg:(UIColor *)bg pressed:(UIColor *)pressed text:(UIColor *)text font:(UIFont *)font {
	k.normalColor = bg;
	k.pressedColor = pressed;
	k.backgroundColor = bg;
	k.layer.cornerRadius = _radius;
	k.titleLabel.font = font;
	[k setTitleColor:text forState:UIControlStateNormal];
}

- (void)updateAutoShift {
	if (_page != 0 || _shiftState == 2) return;
	id<UITextDocumentProxy> p = self.textDocumentProxy;
	NSString *before = p.documentContextBeforeInput ?: @"";
	BOOL want = NO;
	switch (p.autocapitalizationType) {
	case UITextAutocapitalizationTypeAllCharacters:
		want = YES; break;
	case UITextAutocapitalizationTypeWords:
		want = before.length == 0 || [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[before characterAtIndex:before.length - 1]];
		break;
	case UITextAutocapitalizationTypeSentences:
		want = before.length == 0 || [before hasSuffix:@"\n"] || [before hasSuffix:@". "] || [before hasSuffix:@"! "] || [before hasSuffix:@"? "];
		break;
	default: break;
	}
	NSInteger s = want ? 1 : 0;
	if (s != _shiftState) { _shiftState = s; [self refresh]; }
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self loadConfig];
	[self updateAutoShift];
	[self refresh];
	[self.view setNeedsLayout];
}
- (void)textDidChange:(id<UITextInput>)input { [self updateAutoShift]; [self refresh]; }

#pragma mark - Actions (touch-down for responsiveness, except space)

- (void)charDown:(LKKey *)k {
	[self.textDocumentProxy insertText:[k titleForState:UIControlStateNormal]];
	if (_shiftState == 1) { _shiftState = 0; [self refresh]; }
}

- (void)shiftDown:(LKKey *)k {
	if (_page != 0) { _page = _page == 1 ? 2 : 1; [self refresh]; return; }
	NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
	_shiftState = (now - _lastShiftTap < 0.4) ? 2 : (_shiftState ? 0 : 1);
	_lastShiftTap = now;
	[self refresh];
}

- (void)modeDown:(LKKey *)k { _page = _page == 0 ? 1 : 0; _shiftState = 0; [self refresh]; }
- (void)retDown:(LKKey *)k { [self.textDocumentProxy insertText:@"\n"]; }
- (void)globeDown:(LKKey *)k { [self advanceToNextInputMode]; }
- (void)spaceUp:(LKKey *)k { [self.textDocumentProxy insertText:@" "]; }

- (void)delDown:(LKKey *)k {
	[self.textDocumentProxy deleteBackward];
	[self delUp:k];
	_delayTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(startRepeat) userInfo:nil repeats:NO];
}

- (void)startRepeat {
	_repeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.06 target:self selector:@selector(repeatDelete) userInfo:nil repeats:YES];
}

- (void)repeatDelete { [self.textDocumentProxy deleteBackward]; }

- (void)delUp:(LKKey *)k {
	[_delayTimer invalidate]; _delayTimer = nil;
	[_repeatTimer invalidate]; _repeatTimer = nil;
}

#pragma mark - Swipe on the space bar moves the cursor

- (void)spacePan:(UIPanGestureRecognizer *)g {
	const CGFloat step = 12; // points of travel per character
	if (g.state == UIGestureRecognizerStateBegan) {
		_spaceDragX = 0;
		_spaceMoved = 0;
	} else if (g.state == UIGestureRecognizerStateChanged) {
		CGFloat x = [g translationInView:self.view].x;
		NSInteger n = (NSInteger)((x - _spaceDragX) / step);
		if (n != 0) {
			[self.textDocumentProxy adjustTextPositionByCharacterOffset:n];
			_spaceDragX += n * step;
		}
	}
}

#pragma mark - Long press: accents and diacritics

- (void)longPress:(UILongPressGestureRecognizer *)g {
	LKKey *k = (LKKey *)g.view;
	if (g.state == UIGestureRecognizerStateBegan) {
		NSString *base = [k titleForState:UIControlStateNormal];
		NSString *alts = Accents()[base.lowercaseString];
		if (!alts.length) return;
		BOOL upper = ![base isEqualToString:base.lowercaseString];
		NSMutableArray<NSString *> *opts = [NSMutableArray array];
		[alts enumerateSubstringsInRange:NSMakeRange(0, alts.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *s, NSRange r, NSRange er, BOOL *stop) {
			[opts addObject:upper ? ([s isEqualToString:@"ß"] ? @"ẞ" : s.uppercaseString) : s];
		}];
		_popupBase = base;
		[self showPopup:opts above:k];
	} else if (g.state == UIGestureRecognizerStateChanged) {
		if (_popup) [self highlightPopupAt:[g locationInView:_popup]];
	} else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) {
		if (_popup && g.state == UIGestureRecognizerStateEnded && _popupIndex >= 0) {
			// The base character was inserted on touch-down; swap it for the alternate.
			[self.textDocumentProxy deleteBackward];
			[self.textDocumentProxy insertText:_popupLabels[_popupIndex].text];
		}
		[_popup removeFromSuperview];
		_popup = nil;
		_popupLabels = nil;
	}
}

- (void)showPopup:(NSArray<NSString *> *)opts above:(LKKey *)k {
	CGFloat w = k.bounds.size.width, h = k.bounds.size.height;
	CGFloat total = opts.count * w;
	CGFloat x = MIN(MAX(0, CGRectGetMidX(k.frame) - total / 2), self.view.bounds.size.width - total);
	CGFloat y = CGRectGetMinY(k.frame) - h - 4;
	if (y < 0) y = 0; // top row: no room above, cover the row instead
	BOOL dark = self.textDocumentProxy.keyboardAppearance == UIKeyboardAppearanceDark;
	_popup = [[UIView alloc] initWithFrame:CGRectMake(x, y, total, h)];
	_popup.backgroundColor = dark ? [UIColor colorWithWhite:0.28 alpha:1] : [UIColor whiteColor];
	_popup.layer.cornerRadius = _radius;
	_popup.layer.borderWidth = 1;
	_popup.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:1].CGColor;
	NSMutableArray *labels = [NSMutableArray array];
	for (NSUInteger i = 0; i < opts.count; i++) {
		UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(i * w, 0, w, h)];
		l.text = opts[i];
		l.textAlignment = NSTextAlignmentCenter;
		l.font = [UIFont systemFontOfSize:_font];
		l.textColor = dark ? [UIColor whiteColor] : [UIColor blackColor];
		l.layer.cornerRadius = _radius;
		l.layer.masksToBounds = YES;
		[_popup addSubview:l];
		[labels addObject:l];
	}
	_popupLabels = labels;
	_popupIndex = -1;
	[self.view addSubview:_popup];
}

- (void)highlightPopupAt:(CGPoint)p {
	NSInteger idx = -1;
	if (p.y >= -20 && p.y <= _popup.bounds.size.height + 20 && p.x >= 0 && p.x < _popup.bounds.size.width) {
		idx = (NSInteger)(p.x / (_popup.bounds.size.width / _popupLabels.count));
	}
	_popupIndex = idx;
	BOOL dark = self.textDocumentProxy.keyboardAppearance == UIKeyboardAppearanceDark;
	for (NSInteger i = 0; i < (NSInteger)_popupLabels.count; i++) {
		UILabel *l = _popupLabels[i];
		l.backgroundColor = i == idx ? [UIColor colorWithRed:0.2 green:0.5 blue:1 alpha:1] : [UIColor clearColor];
		l.textColor = i == idx ? [UIColor whiteColor] : (dark ? [UIColor whiteColor] : [UIColor blackColor]);
	}
}

@end
