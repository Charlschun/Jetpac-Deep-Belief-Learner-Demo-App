//
//  ViewController.m
//  Jetpac Deep Belief Learner
//
//  Created by Dave Fearon on 4/10/14.
//  Copyright (c) 2014 Jetpac. All rights reserved.
//

#import "ViewController.h"
#import "CustomButton.H"

#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>
#include <sys/time.h>
#import <sys/utsname.h>
#import "QuartzCore/QuartzCore.h"

#import <DeepBelief/DeepBelief.h>

const int kPositivePredictionTotal = 100;
const int kNegativePredictionTotal = 100;
const int kElementsPerPrediction = 4096;

const float kMinSecondsBetweenPings = 0.5f;

enum EPredictionState {
    eWaiting,
    ePositiveLearning,
    eNegativeWaiting,
    eNegativeLearning,
    ePredicting,
};

static const NSString *AVCaptureStillImageIsCapturingStillImageContext = @"AVCaptureStillImageIsCapturingStillImageContext";

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};

// utility used by newSquareOverlayedImageForFeatures for
static CGContextRef CreateCGBitmapContextForSize(CGSize size);
static CGContextRef CreateCGBitmapContextForSize(CGSize size)
{
    CGContextRef    context = NULL;
    CGColorSpaceRef colorSpace;
    int             bitmapBytesPerRow;
	
    bitmapBytesPerRow = (size.width * 4);
	
    colorSpace = CGColorSpaceCreateDeviceRGB();
    context = CGBitmapContextCreate (NULL,
									 size.width,
									 size.height,
									 8,      // bits per component
									 bitmapBytesPerRow,
									 colorSpace,
									 kCGImageAlphaPremultipliedLast);
	CGContextSetAllowsAntialiasing(context, NO);
    CGColorSpaceRelease( colorSpace );
    return context;
}

@interface UIImage (RotationMethods)
- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees;
@end

@implementation UIImage (RotationMethods)

- (UIImage *)imageRotatedByDegrees:(CGFloat)degrees
{
	// calculate the size of the rotated view's containing box for our drawing space
	UIView *rotatedViewBox = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.size.width, self.size.height)];
	CGAffineTransform t = CGAffineTransformMakeRotation(DegreesToRadians(degrees));
	rotatedViewBox.transform = t;
	CGSize rotatedSize = rotatedViewBox.frame.size;
	
	// Create the bitmap context
	UIGraphicsBeginImageContext(rotatedSize);
	CGContextRef bitmap = UIGraphicsGetCurrentContext();
	
	// Move the origin to the middle of the image so we will rotate and scale around the center.
	CGContextTranslateCTM(bitmap, rotatedSize.width/2, rotatedSize.height/2);
	
	//   // Rotate the image context
	CGContextRotateCTM(bitmap, DegreesToRadians(degrees));
	
	// Now, draw the rotated/scaled image into the context
	CGContextScaleCTM(bitmap, 1.0, -1.0);
	CGContextDrawImage(bitmap, CGRectMake(-self.size.width / 2, -self.size.height / 2, self.size.width, self.size.height), [self CGImage]);
	
	UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return newImage;
}

@end

@interface ViewController (InternalMethods)
- (void)setupAVCapture;
- (void)teardownAVCapture;
- (void)drawFaceBoxesForFeatures:(NSArray *)features forVideoBox:(CGRect)clap orientation:(UIDeviceOrientation)orientation;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    iphoneModel = [self machineName];
    
    [self setupScreenElements];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    [[UIApplication sharedApplication] setStatusBarHidden: NO withAnimation:UIStatusBarAnimationSlide];
    [self.view setBackgroundColor:[UIColor colorWithRed:17.0/255.0 green:17.0/255.0 blue:17.0/255.0 alpha:1.0]];
    
    NSString* networkPath = [[NSBundle mainBundle] pathForResource:@"jetpac" ofType:@"ntwk"];
    if (networkPath == NULL)
    {
        fprintf(stderr, "Couldn't find the neural network parameters file - did you add it as a resource to your application?\n");
        assert(false);
    }
    network = jpcnn_create_network([networkPath UTF8String]);
    assert(network != NULL);
    
    [self setupLearning];
    
    [self setupAVCapture];
    square = [UIImage imageNamed:@"squarePNG"];
	NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
	faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions];
    
//    [self.saveImage setHidden:YES];
    
//    [self.view bringSubviewToFront:introView];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0
                                     target:self
                                   selector:@selector(postTimerFinishLoading:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)setupScreenElements
{
    if ([iphoneModel  isEqual: @"iPhone3,1"] || [iphoneModel  isEqual: @"iPhone4,1"])
    {
        //        short version
        //        CGRect viewFrame = previewView.frame;
        //        CGSize newSize = CGSizeMake(viewFrame.size.width, viewFrame.size.height - 90.0);
        //        viewFrame.size = newSize;
        //        [previewView setFrame:viewFrame];
        //        [previewView setBackgroundColor:[UIColor colorWithRed:17.0/255.0 green:17.0/255.0 blue:17.0/255.0 alpha:1.0]];
        //        [introView setFrame:viewFrame];
        
//        CGRect frame = self.saveImage.frame;
//        frame.origin.x = frame.origin.x; // new x coordinate
//        frame.origin.y = self.view.frame.size.height - 70.0; // new y coordinate
//        [self.saveImage setFrame:frame];
        
        [self.view setBackgroundColor:[UIColor colorWithRed:17.0/255.0 green:17.0/255.0 blue:17.0/255.0 alpha:1.0]];
    } else {
        //        tall version
    }
}

- (NSString*)machineName
{
    //    @"i386"      on the simulator
    //    @"iPod1,1"   on iPod Touch
    //    @"iPod2,1"   on iPod Touch Second Generation
    //    @"iPod3,1"   on iPod Touch Third Generation
    //    @"iPod4,1"   on iPod Touch Fourth Generation
    //    @"iPhone1,1" on iPhone
    //    @"iPhone1,2" on iPhone 3G
    //    @"iPhone2,1" on iPhone 3GS
    //    @"iPad1,1"   on iPad
    //    @"iPad2,1"   on iPad 2
    //    @"iPad3,1"   on iPad 3 (aka new iPad)
    //    @"iPhone3,1" on iPhone 4
    //    @"iPhone4,1" on iPhone 4S
    //    @"iPhone5,1" on iPhone 5
    //    @"iPhone5,2" on iPhone 5
    struct utsname systemInfo;
    uname(&systemInfo);
    
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

- (void)postTimerFinishLoading:(NSTimer *)timer
{
    [timer invalidate];
    timer = nil;
    
//    [introView setHidden:YES];
//    [introView removeFromSuperview];
    
//    [self.saveImage setHidden:YES];
    
    [self createButton];
    
    synth = [[AVSpeechSynthesizer alloc] init];
    
    labelLayers = [[NSMutableArray alloc] init];
    
    oldPredictionValues = [[NSMutableDictionary alloc] init];
    
    gradientLayer = [[UIView alloc] init];
    CAGradientLayer *gradient = [CAGradientLayer layer];
    
    gradient.frame = previewView.bounds;
    [gradient setFrame:CGRectMake(0, 0, previewView.bounds.size.width, previewView.bounds.size.height / 2.0)];
    [gradient setColors:[NSArray arrayWithObjects:(id)[[UIColor blackColor] CGColor], (id)[[UIColor clearColor] CGColor], nil]];
    [gradientLayer.layer insertSublayer:gradient atIndex:0];
    [previewView addSubview:gradientLayer];
    [previewView bringSubviewToFront:gradientLayer];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    //    NSLog(@"view will appear");
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    //    NSLog(@"view did appear");
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)appDidBecomeActive:(NSNotification *)notification
{
    //    NSLog(@"did become active notification");
}

- (void)appDidEnterForeground:(NSNotification *)notification
{
    //    NSLog(@"did enter foreground notification");
    //    [actionButton.layer setBackgroundColor:[UIColor colorWithRed:92.0/255.0 green:92.0/255.0 blue:92.0/255.0 alpha:1.0].CGColor];
    [actionButton.layer setBackgroundColor:[UIColor blackColor].CGColor];
    [actionButton setTitleColor:[UIColor colorWithRed:137.0/255.0 green:137.0/255.0 blue:137.0/255.0 alpha:1.0] forState:UIControlStateNormal];
    [actionButton setTitleColor:[UIColor colorWithRed:137.0/255.0 green:137.0/255.0 blue:137.0/255.0 alpha:0.5] forState:UIControlStateHighlighted];
    [actionButton.layer setBorderColor:[UIColor colorWithRed:92.0/255.0 green:92.0/255.0 blue:92.0/255.0 alpha:1.0].CGColor];
    [actionButton setTitle: @"Start Teaching" forState:UIControlStateNormal];

    [session startRunning];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
	if ( [gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]] )
    {
		beginGestureScale = effectiveScale;
	}
	return YES;
}

- (IBAction)handlePinchGesture:(UIPinchGestureRecognizer *)recognizer
{
	BOOL allTouchesAreOnThePreviewLayer = YES;
	NSUInteger numTouches = [recognizer numberOfTouches], i;
	for ( i = 0; i < numTouches; ++i )
    {
		CGPoint location = [recognizer locationOfTouch:i inView:previewView];
		CGPoint convertedLocation = [previewLayer convertPoint:location fromLayer:previewLayer.superlayer];
		if ( ! [previewLayer containsPoint:convertedLocation] )
        {
			allTouchesAreOnThePreviewLayer = NO;
			break;
		}
	}
	
	if ( allTouchesAreOnThePreviewLayer )
    {
		effectiveScale = beginGestureScale * recognizer.scale;
		if (effectiveScale < 1.0)
        {
            effectiveScale = 1.0;
        }
		CGFloat maxScaleAndCropFactor = [[stillImageOutput connectionWithMediaType:AVMediaTypeVideo] videoMaxScaleAndCropFactor];
		if (effectiveScale > maxScaleAndCropFactor)
        {
			effectiveScale = maxScaleAndCropFactor;
        }
		[CATransaction begin];
		[CATransaction setAnimationDuration:.025];
		[previewLayer setAffineTransform:CGAffineTransformMakeScale(effectiveScale, effectiveScale)];
		[CATransaction commit];
	}
}

- (void)dealloc
{
    [self teardownAVCapture];
}

- (IBAction)switchCameras:(id)sender
{
	AVCaptureDevicePosition desiredPosition;
	if (isUsingFrontFacingCamera)
    {
		desiredPosition = AVCaptureDevicePositionBack;
    }
	else
    {
		desiredPosition = AVCaptureDevicePositionFront;
    }
	
	for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo])
    {
		if ([d position] == desiredPosition)
        {
			[[previewLayer session] beginConfiguration];
			AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:d error:nil];
			for (AVCaptureInput *oldInput in [[previewLayer session] inputs])
            {
				[[previewLayer session] removeInput:oldInput];
			}
			[[previewLayer session] addInput:input];
			[[previewLayer session] commitConfiguration];
			break;
		}
	}
	isUsingFrontFacingCamera = !isUsingFrontFacingCamera;
}

- (AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
	AVCaptureVideoOrientation result = deviceOrientation;
	if ( deviceOrientation == UIDeviceOrientationLandscapeLeft )
    {
		result = AVCaptureVideoOrientationLandscapeRight;
    }
	else if ( deviceOrientation == UIDeviceOrientationLandscapeRight )
    {
		result = AVCaptureVideoOrientationLandscapeLeft;
    }
	return result;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ( context == (__bridge void *)(AVCaptureStillImageIsCapturingStillImageContext) )
    {
		BOOL isCapturingStillImage = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
		
		if ( isCapturingStillImage )
        {
			// do flash bulb like animation
			flashView = [[UIView alloc] initWithFrame:[previewView frame]];
			[flashView setBackgroundColor:[UIColor whiteColor]];
			[flashView setAlpha:0.f];
			[[[self view] window] addSubview:flashView];
			
			[UIView animateWithDuration:.4f
							 animations:^{
								 [flashView setAlpha:1.f];
							 }
			 ];
		}
		else
        {
			[UIView animateWithDuration:.4f
							 animations:^{
								 [flashView setAlpha:0.f];
							 }
							 completion:^(BOOL finished){
								 [flashView removeFromSuperview];
								 flashView = nil;
							 }
			 ];
		}
	}
}

- (void)createButton
{
    actionButton = [CustomButton buttonWithType:UIButtonTypeCustom];
    [actionButton addTarget:self action:@selector(takePicture:) forControlEvents:UIControlEventTouchUpInside];
    [actionButton setTitle:@"Start Teaching" forState:UIControlStateNormal];
    
    [actionButton setTitleColor:[UIColor colorWithRed:137.0/255.0 green:137.0/255.0 blue:137.0/255.0 alpha:1.0] forState:UIControlStateNormal];
    [actionButton setTitleColor:[UIColor colorWithRed:137.0/255.0 green:137.0/255.0 blue:137.0/255.0 alpha:0.5] forState:UIControlStateHighlighted];
    
    [actionButton.layer setCornerRadius:37.0];
    [actionButton.layer setBorderColor:[UIColor colorWithRed:92.0/255.0 green:92.0/255.0 blue:92.0/255.0 alpha:1.0].CGColor];
    //    [actionButton.layer setBorderColor:[UIColor whiteColor].CGColor];
    
    //    [actionButton.layer setBackgroundColor:[UIColor redColor].CGColor];
    //    [actionButton.layer setBackgroundColor:[UIColor colorWithRed:92.0/255.0 green:92.0/255.0 blue:92.0/255.0 alpha:1.0].CGColor];
    //    [actionButton setBackgroundImage:[UIImage imageNamed:@"stillBtn.png"] forState:UIControlStateNormal];
    //    [actionButton setBackgroundImage:[UIImage imageNamed:@"stillBtn.png"] forState:UIControlStateHighlighted];
    [actionButton.layer setBackgroundColor:[UIColor blackColor].CGColor];
    
    [actionButton.layer setBorderWidth:3];
    [actionButton.layer setMasksToBounds:YES];
    //    [button setFrame:CGRectMake((self.view.bounds.size.width / 2.0) - 50.0, self.view.bounds.size.height - 110.0, 100.0, 100.0)];
    [actionButton setFrame:CGRectMake((self.view.bounds.size.width / 2.0) - 87.0, self.view.bounds.size.height - 77.0, 174.0, 74.0)];
    //    [button setContentEdgeInsets:UIEdgeInsetsMake(25, 0, 25, 0)];
    [self.view addSubview:actionButton];
}

- (void)setupLearning
{
    negativePredictionsCount = 0;

    trainer = NULL;
    predictor = NULL;
    predictionState = eWaiting;

    lastInfo = NULL;

    [self setupInfoDisplay];
    [self setupSound];
}

- (void)setupInfoDisplay
{
    NSString * const font = @"Helvetica-Neue-Medium";
    const float fontSize = 16.0f;
    
    const float viewWidth = 320.0f;
    
    const float marginSizeX = 5.0f;
    const float marginSizeY = 5.0f;
    const float marginTopY = 7.0f;
    
    const float progressHeight = 20.0f;
    
    const float infoHeight = 150.0f;
    
    const CGRect progressBackgroundBounds = CGRectMake(marginSizeX, 25.0 + marginTopY, (viewWidth - (marginSizeX * 2)), progressHeight);
    
    self.progressBackground = [CATextLayer layer];
    [self.progressBackground setBackgroundColor: [UIColor blackColor].CGColor];
    [self.progressBackground setOpacity:0.5f];
    [self.progressBackground setFrame: progressBackgroundBounds];
    self.progressBackground.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer: self.progressBackground];
    
    const CGRect progressForegroundBounds = CGRectMake(marginSizeX, 25.0 + marginTopY, 0.0f, progressHeight);
    
    self.progressForeground = [CATextLayer layer];
    [self.progressForeground setBackgroundColor: [UIColor blueColor].CGColor];
    [self.progressForeground setOpacity:0.75f];
    [self.progressForeground setFrame: progressForegroundBounds];
    self.progressForeground.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer: self.progressForeground];
    
    const CGRect infoBackgroundBounds = CGRectMake(marginSizeX, 35.0 + (marginSizeY + progressHeight + marginSizeY), (viewWidth - (marginSizeX * 2)), infoHeight);
    
    self.infoBackground = [CATextLayer layer];
    [self.infoBackground setBackgroundColor: [UIColor clearColor].CGColor];
    [self.infoBackground setOpacity:0.5f];
    [self.infoBackground setFrame: infoBackgroundBounds];
    self.infoBackground.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer: self.infoBackground];
    
    const CGRect infoForegroundBounds = CGRectInset(infoBackgroundBounds, 5.0f, 5.0f);
    
    self.infoForeground = [CATextLayer layer];
    [self.infoForeground setBackgroundColor: [UIColor clearColor].CGColor];
    [self.infoForeground setForegroundColor: [UIColor whiteColor].CGColor];
    [self.infoForeground setOpacity:1.0f];
    [self.infoForeground setFrame: infoForegroundBounds];
    [self.infoForeground setWrapped: YES];
    [self.infoForeground setFont: (__bridge CFTypeRef)(font)];
    [self.infoForeground setFontSize: fontSize];
    self.infoForeground.alignmentMode = kCAAlignmentCenter;
    self.infoForeground.contentsScale = [[UIScreen mainScreen] scale];
    
    [self.infoForeground setString: @""];
    
    [[self.view layer] addSublayer: self.infoForeground];
}

- (void)setupSound
{
    // Create the URL for the source audio file. The URLForResource:withExtension: method is
    //    new in iOS 4.0.
    NSURL *soundUrl   = [[NSBundle mainBundle] URLForResource: @"32093__jbum__jsyd-ping"
                                                withExtension: @"wav"];
    self.soundFileURLRef = (__bridge CFURLRef) soundUrl;
    
    // Create a system sound object representing the sound file.
    AudioServicesCreateSystemSoundID (
                                      self.soundFileURLRef,
                                      &_soundFileObject
                                      );
}

- (void)setupAVCapture
{
	NSError *error = nil;
	
	session = [AVCaptureSession new];
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        [session setSessionPreset:AVCaptureSessionPreset640x480];
    }
	else
    {
        [session setSessionPreset:AVCaptureSessionPresetPhoto];
    }
	
    // Select a video device, make an input
	AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    //	require( error == nil, bail );
	
    isUsingFrontFacingCamera = NO;
	if ( [session canAddInput:deviceInput] )
    {
		[session addInput:deviceInput];
    }
	
    // Make a still image output
	stillImageOutput = [AVCaptureStillImageOutput new];
	[stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:(__bridge void *)(AVCaptureStillImageIsCapturingStillImageContext)];
	if ( [session canAddOutput:stillImageOutput] )
    {
		[session addOutput:stillImageOutput];
    }
	
    // Make a video data output
	videoDataOutput = [AVCaptureVideoDataOutput new];
	
    // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
	NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:
									   [NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
	[videoDataOutput setVideoSettings:rgbOutputSettings];
	[videoDataOutput setAlwaysDiscardsLateVideoFrames:YES]; // discard if the data output queue is blocked (as we process the still image)
    
    // create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured
    // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
    // see the header doc for setSampleBufferDelegate:queue: for more information
	videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
	[videoDataOutput setSampleBufferDelegate:self queue:videoDataOutputQueue];
	
    if ( [session canAddOutput:videoDataOutput] )
    {
		[session addOutput:videoDataOutput];
    }
	[[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
	detectFaces = YES;
    
	effectiveScale = 1.0;
	previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
	[previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
	[previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
	CALayer *rootLayer = [previewView layer];
	[rootLayer setMasksToBounds:YES];
    
    [previewLayer setBounds:CGRectMake(0, 0, rootLayer.bounds.size.width, rootLayer.bounds.size.height)];
	[previewLayer setFrame:[rootLayer bounds]];
	[rootLayer addSublayer:previewLayer];
	[session startRunning];
bail:
	if (error)
    {
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"Failed with error %d", (int)[error code]]
															message:[error localizedDescription]
														   delegate:nil
												  cancelButtonTitle:@"Dismiss"
												  otherButtonTitles:nil];
		[alertView show];
		[self teardownAVCapture];
	}
}

- (void)teardownAVCapture
{
	[stillImageOutput removeObserver:self forKeyPath:@"isCapturingStillImage"];
	[previewLayer removeFromSuperlayer];
}

- (IBAction)toggleFaceDetection:(id)sender
{
	detectFaces = [(UISwitch *)sender isOn];
	[[videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:detectFaces];
	if (!detectFaces)
    {
		dispatch_async(dispatch_get_main_queue(), ^(void) {
			// clear out any squares currently displaying.
			[self drawFaceBoxesForFeatures:[NSArray array] forVideoBox:CGRectZero orientation:UIDeviceOrientationPortrait];
		});
	}
}

+ (CGRect)videoPreviewBoxForGravity:(NSString *)gravity frameSize:(CGSize)frameSize apertureSize:(CGSize)apertureSize
{
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill])
    {
        if (viewRatio > apertureRatio)
        {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        }
        else
        {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
    }
    else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect])
    {
        if (viewRatio > apertureRatio)
        {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
        else
        {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        }
    }
    else if ([gravity isEqualToString:AVLayerVideoGravityResize])
    {
        size.width = frameSize.width;
        size.height = frameSize.height;
    }
	
	CGRect videoBox;
	videoBox.size = size;
	if (size.width < frameSize.width)
    {
		videoBox.origin.x = (frameSize.width - size.width) / 2;
    }
	else
    {
		videoBox.origin.x = (size.width - frameSize.width) / 2;
    }
	
	if ( size.height < frameSize.height )
    {
		videoBox.origin.y = (frameSize.height - size.height) / 2;
    }
	else
    {
		videoBox.origin.y = (size.height - frameSize.height) / 2;
    }
    
	return videoBox;
}

- (void)drawFaceBoxesForFeatures:(NSArray *)features forVideoBox:(CGRect)clap orientation:(UIDeviceOrientation)orientation
{
	NSArray *sublayers = [NSArray arrayWithArray:[previewLayer sublayers]];
	NSInteger sublayersCount = [sublayers count], currentSublayer = 0;
	NSInteger featuresCount = [features count], currentFeature = 0;
	
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
	
	// hide all the face layers
	for ( CALayer *layer in sublayers )
    {
		if ( [[layer name] isEqualToString:@"FaceLayer"] )
        {
			[layer setHidden:YES];
        }
	}
    
	if ( featuresCount == 0 || !detectFaces )
    {
		[CATransaction commit];
		return; // early bail.
	}
    
	CGSize parentFrameSize = [previewView frame].size;
	NSString *gravity = [previewLayer videoGravity];
	BOOL isMirrored = [previewLayer isMirrored];
	CGRect previewBox = [ViewController videoPreviewBoxForGravity:gravity
                                                        frameSize:parentFrameSize
                                                     apertureSize:clap.size];
	
	for ( CIFaceFeature *ff in features )
    {
		// find the correct position for the square layer within the previewLayer
		// the feature box originates in the bottom left of the video frame.
		// (Bottom right if mirroring is turned on)
		CGRect faceRect = [ff bounds];
        
		// flip preview width and height
		CGFloat temp = faceRect.size.width;
		faceRect.size.width = faceRect.size.height;
		faceRect.size.height = temp;
		temp = faceRect.origin.x;
		faceRect.origin.x = faceRect.origin.y;
		faceRect.origin.y = temp;
		// scale coordinates so they fit in the preview box, which may be scaled
		CGFloat widthScaleBy = previewBox.size.width / clap.size.height;
		CGFloat heightScaleBy = previewBox.size.height / clap.size.width;
		faceRect.size.width *= widthScaleBy;
		faceRect.size.height *= heightScaleBy;
		faceRect.origin.x *= widthScaleBy;
		faceRect.origin.y *= heightScaleBy;
        
		if ( isMirrored )
        {
			faceRect = CGRectOffset(faceRect, previewBox.origin.x + previewBox.size.width - faceRect.size.width - (faceRect.origin.x * 2), previewBox.origin.y);
        }
		else
        {
			faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y);
        }
		
		CALayer *featureLayer = nil;
		
		// re-use an existing layer if possible
		while ( !featureLayer && (currentSublayer < sublayersCount) )
        {
			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
			if ( [[currentLayer name] isEqualToString:@"FaceLayer"] )
            {
				featureLayer = currentLayer;
				[currentLayer setHidden:NO];
			}
		}
		
		// create a new one if necessary
		if ( !featureLayer )
        {
			featureLayer = [CALayer new];
			[featureLayer setContents:(id)[square CGImage]];
			[featureLayer setName:@"FaceLayer"];
			[previewLayer addSublayer:featureLayer];
		}
		[featureLayer setFrame:faceRect];
		
		switch (orientation)
        {
			case UIDeviceOrientationPortrait:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
				break;
			case UIDeviceOrientationPortraitUpsideDown:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
				break;
			case UIDeviceOrientationLandscapeLeft:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
				break;
			case UIDeviceOrientationLandscapeRight:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
				break;
			case UIDeviceOrientationFaceUp:
			case UIDeviceOrientationFaceDown:
			default:
				break; // leave the layer in its last known orientation
		}
		currentFeature++;
	}
	
	[CATransaction commit];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    [self runCNNOnFrame:pixelBuffer];
}

- (IBAction)takePicture:(id)sender
{
    switch (predictionState) {
        case eWaiting: {
            [sender setTitle: @"Teaching" forState:UIControlStateNormal];
            [self triggerNextState];
        } break;
            
        case ePositiveLearning: {
            // Do nothing
        } break;
            
        case eNegativeWaiting: {
            [sender setTitle: @"Teaching" forState:UIControlStateNormal];
            [self triggerNextState];
        } break;
            
        case eNegativeLearning: {
            // Do nothing
        } break;
            
        case ePredicting: {
            [self triggerNextState];
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
}

- (CGImageRef)newSquareOverlayedImageForFeatures:(NSArray *)features
                                       inCGImage:(CGImageRef)backgroundImage
                                 withOrientation:(UIDeviceOrientation)orientation
                                     frontFacing:(BOOL)isFrontFacing
{
	CGImageRef returnImage = NULL;
	CGRect backgroundImageRect = CGRectMake(0., 0., CGImageGetWidth(backgroundImage), CGImageGetHeight(backgroundImage));
	CGContextRef bitmapContext = CreateCGBitmapContextForSize(backgroundImageRect.size);
	CGContextClearRect(bitmapContext, backgroundImageRect);
	CGContextDrawImage(bitmapContext, backgroundImageRect, backgroundImage);
	CGFloat rotationDegrees = 0.;
	
	switch (orientation)
    {
		case UIDeviceOrientationPortrait:
			rotationDegrees = -90.;
			break;
		case UIDeviceOrientationPortraitUpsideDown:
			rotationDegrees = 90.;
			break;
		case UIDeviceOrientationLandscapeLeft:
			if (isFrontFacing) rotationDegrees = 180.;
			else rotationDegrees = 0.;
			break;
		case UIDeviceOrientationLandscapeRight:
			if (isFrontFacing) rotationDegrees = 0.;
			else rotationDegrees = 180.;
			break;
		case UIDeviceOrientationFaceUp:
		case UIDeviceOrientationFaceDown:
		default:
			break; // leave the layer in its last known orientation
	}
	UIImage *rotatedSquareImage = [square imageRotatedByDegrees:rotationDegrees];
	
    // features found by the face detector
	for ( CIFaceFeature *ff in features )
    {
		CGRect faceRect = [ff bounds];
		CGContextDrawImage(bitmapContext, faceRect, [rotatedSquareImage CGImage]);
	}
	returnImage = CGBitmapContextCreateImage(bitmapContext);
	CGContextRelease (bitmapContext);
	
	return returnImage;
}

- (BOOL)writeCGImageToCameraRoll:(CGImageRef)cgImage withMetadata:(NSDictionary *)metadata
{
	CFMutableDataRef destinationData = CFDataCreateMutable(kCFAllocatorDefault, 0);
	CGImageDestinationRef destination = CGImageDestinationCreateWithData(destinationData,
																		 CFSTR("public.jpeg"),
																		 1,
																		 NULL);
	BOOL success = (destination != NULL);
    //	require(success, bail);
    
	const float JPEGCompQuality = 0.85f; // JPEGHigherQuality
	CFMutableDictionaryRef optionsDict = NULL;
	CFNumberRef qualityNum = NULL;
	
	qualityNum = CFNumberCreate(0, kCFNumberFloatType, &JPEGCompQuality);
	if ( qualityNum )
    {
		optionsDict = CFDictionaryCreateMutable(0, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
		if ( optionsDict )
        {
			CFDictionarySetValue(optionsDict, kCGImageDestinationLossyCompressionQuality, qualityNum);
        }
		CFRelease( qualityNum );
	}
	
	CGImageDestinationAddImage( destination, cgImage, optionsDict );
	success = CGImageDestinationFinalize( destination );
    
	if ( optionsDict )
    {
		CFRelease(optionsDict);
    }
	
    //	require(success, bail);
	
	CFRetain(destinationData);
	ALAssetsLibrary *library = [ALAssetsLibrary new];
	[library writeImageDataToSavedPhotosAlbum:(__bridge id)destinationData metadata:metadata completionBlock:^(NSURL *assetURL, NSError *error) {
		if (destinationData)
        {
			CFRelease(destinationData);
        }
	}];
    
    
bail:
	if (destinationData)
    {
		CFRelease(destinationData);
    }
	if (destination)
    {
		CFRelease(destination);
    }
	return success;
}

- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message
{
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
															message:[error localizedDescription]
														   delegate:nil
												  cancelButtonTitle:@"Dismiss"
												  otherButtonTitles:nil];
		[alertView show];
	});
}

- (void)removeAllLabelLayers
{
    for (CATextLayer* layer in labelLayers)
    {
        [layer removeFromSuperlayer];
    }
    [labelLayers removeAllObjects];
}

- (void)addLabelLayerWithText: (NSString*) text
                      originX:(float) originX originY:(float) originY
                        width:(float) width height:(float) height
                    alignment:(NSString*) alignment
{
    NSString* const font = @"Menlo-Regular";
    const float fontSize = 20.0f;
    const float marginSizeX = 5.0f;
    const float marginSizeY = 2.0f;
    const CGRect backgroundBounds = CGRectMake(originX, originY, width, height);
    const CGRect textBounds = CGRectMake((originX + marginSizeX), (originY + marginSizeY),
                                         (width - (marginSizeX * 2)), (height - (marginSizeY * 2)));
    
    CATextLayer* background = [CATextLayer layer];
    [background setBackgroundColor: [UIColor clearColor].CGColor];
    [background setOpacity:0.5f];
    [background setFrame: backgroundBounds];
    background.cornerRadius = 5.0f;
    
    [[self.view layer] addSublayer: background];
    [labelLayers addObject: background];
    
    CATextLayer *layer = [CATextLayer layer];
    [layer setForegroundColor: [UIColor whiteColor].CGColor];
    [layer setFrame: textBounds];
    [layer setAlignmentMode: alignment];
    [layer setWrapped: YES];
    [layer setFont: (__bridge CFTypeRef)(font)];
    [layer setFontSize: fontSize];
    layer.contentsScale = [[UIScreen mainScreen] scale];
    [layer setString: text];
    
    [[self.view layer] addSublayer: layer];
    [labelLayers addObject: layer];
}

- (void)runCNNOnFrame: (CVPixelBufferRef) pixelBuffer
{
    assert(pixelBuffer != NULL);
    
	OSType sourcePixelFormat = CVPixelBufferGetPixelFormatType( pixelBuffer );
    int doReverseChannels;
	if ( kCVPixelFormatType_32ARGB == sourcePixelFormat )
    {
        doReverseChannels = 1;
	}
    else if ( kCVPixelFormatType_32BGRA == sourcePixelFormat )
    {
        doReverseChannels = 0;
	}
    else
    {
        assert(false); // Unknown source format
    }
    
	const int sourceRowBytes = (int)CVPixelBufferGetBytesPerRow( pixelBuffer );
	const int width = (int)CVPixelBufferGetWidth( pixelBuffer );
	const int fullHeight = (int)CVPixelBufferGetHeight( pixelBuffer );
	CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
	unsigned char* sourceBaseAddr = CVPixelBufferGetBaseAddress( pixelBuffer );
    int height;
    unsigned char* sourceStartAddr;
    if (fullHeight <= width)
    {
        height = fullHeight;
        sourceStartAddr = sourceBaseAddr;
    }
    else
    {
        height = width;
        const int marginY = ((fullHeight - width) / 2);
        sourceStartAddr = (sourceBaseAddr + (marginY * sourceRowBytes));
    }
    void* cnnInput = jpcnn_create_image_buffer_from_uint8_data(sourceStartAddr, width, height, 4, sourceRowBytes, doReverseChannels, 1);
    float* predictions;
    int predictionsLength;
    char** predictionsLabels;
    int predictionsLabelsLength;
    
    struct timeval start;
    gettimeofday(&start, NULL);
    jpcnn_classify_image(network, cnnInput, JPCNN_RANDOM_SAMPLE, 0, &predictions, &predictionsLength, &predictionsLabels, &predictionsLabelsLength);
    struct timeval end;
    gettimeofday(&end, NULL);
    const long seconds  = end.tv_sec  - start.tv_sec;
    const long useconds = end.tv_usec - start.tv_usec;
    const float duration = ((seconds) * 1000 + useconds/1000.0) + 0.5;
    //    NSLog(@"Took %f ms", duration);
    
    jpcnn_destroy_image_buffer(cnnInput);
    
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        [self handleNetworkPredictions: predictions withLength: predictionsLength];
    });
}

- (void)setEmptyPredictionValue: (NSDictionary *)newValues
{
    NSArray* candidateLabels = [NSMutableArray array];
    for (NSString* label in newValues)
    {
        NSNumber* oldPredictionValueObject = [newValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        NSDictionary *entry = @{
                                @"label" : label,
                                @"value" : oldPredictionValueObject
                                };
        candidateLabels = [candidateLabels arrayByAddingObject: entry];
    }
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"value" ascending:NO];
    NSArray* sortedLabels = [candidateLabels sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]];
    
    const float leftMargin = 10.0f;
    const float topMargin = 65.0f;
    
    const float valueWidth = 48.0f;
    const float valueHeight = 26.0f;
    
    const float labelWidth = 246.0f;
    const float labelHeight = 26.0f;
    
    const float labelMarginX = 5.0f;
    const float labelMarginY = 5.0f;
    
    [self removeAllLabelLayers];
    
    int labelCount = 0;
    for (NSDictionary* entry in sortedLabels)
    {
        NSString *label = [entry objectForKey: @"label"];
        NSNumber *valueObject = [entry objectForKey: @"value"];
        const float value = [valueObject floatValue];
        
        const float originY = (topMargin + ((labelHeight + labelMarginY) * labelCount));
        
        const int valuePercentage = (int)roundf(value * 100.0f);
        
        const float valueOriginX = leftMargin;
        NSString* valueText = [NSString stringWithFormat:@"%d%%", valuePercentage];
        
        [self addLabelLayerWithText:valueText
                            originX:valueOriginX originY:originY
                              width:valueWidth height:valueHeight
                          alignment: kCAAlignmentRight];
        
        const float labelOriginX = (leftMargin + valueWidth + labelMarginX);
        
        [self addLabelLayerWithText: [label capitalizedString]
                            originX: labelOriginX originY: originY
                              width: labelWidth height: labelHeight
                          alignment:kCAAlignmentLeft];
        
        labelCount += 1;
        if (labelCount > 4)
        {
            break;
        }
    }
}

- (void)setPredictionValues: (NSDictionary*) newValues
{
    const float decayValue = 0.75f;
    const float updateValue = 0.25f;
    const float minimumThreshold = 0.01f;
    
    NSMutableDictionary* decayedPredictionValues = [[NSMutableDictionary alloc] init];
    for (NSString* label in oldPredictionValues)
    {
        NSNumber* oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        const float decayedPredictionValue = (oldPredictionValue * decayValue);
        if (decayedPredictionValue > minimumThreshold)
        {
            NSNumber* decayedPredictionValueObject = [NSNumber numberWithFloat: decayedPredictionValue];
            [decayedPredictionValues setObject: decayedPredictionValueObject forKey:label];
        }
    }
    oldPredictionValues = decayedPredictionValues;
    
    for (NSString* label in newValues)
    {
        NSNumber* newPredictionValueObject = [newValues objectForKey:label];
        NSNumber* oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        if (!oldPredictionValueObject)
        {
            oldPredictionValueObject = [NSNumber numberWithFloat: 0.0f];
        }
        const float newPredictionValue = [newPredictionValueObject floatValue];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        const float updatedPredictionValue = (oldPredictionValue + (newPredictionValue * updateValue));
        NSNumber* updatedPredictionValueObject = [NSNumber numberWithFloat: updatedPredictionValue];
        [oldPredictionValues setObject: updatedPredictionValueObject forKey:label];
    }
    NSArray* candidateLabels = [NSMutableArray array];
    for (NSString* label in oldPredictionValues)
    {
        NSNumber* oldPredictionValueObject = [oldPredictionValues objectForKey:label];
        const float oldPredictionValue = [oldPredictionValueObject floatValue];
        if (oldPredictionValue > 0.05f)
        {
            NSDictionary *entry = @{
                                    @"label" : label,
                                    @"value" : oldPredictionValueObject
                                    };
            candidateLabels = [candidateLabels arrayByAddingObject: entry];
        }
    }
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"value" ascending:NO];
    NSArray* sortedLabels = [candidateLabels sortedArrayUsingDescriptors:[NSArray arrayWithObject:sort]];
    
    const float leftMargin = 10.0f;
    const float topMargin = 65.0f;
    
    const float valueWidth = 48.0f;
    const float valueHeight = 26.0f;
    
    const float labelWidth = 246.0f;
    const float labelHeight = 26.0f;
    
    const float labelMarginX = 5.0f;
    const float labelMarginY = 5.0f;
    
    [self removeAllLabelLayers];
    
    int labelCount = 0;
    for (NSDictionary* entry in sortedLabels)
    {
        NSString *label = [entry objectForKey: @"label"];
        NSNumber *valueObject = [entry objectForKey: @"value"];
        const float value = [valueObject floatValue];
        
        const float originY = (topMargin + ((labelHeight + labelMarginY) * labelCount));
        
        const int valuePercentage = (int)roundf(value * 100.0f);
        
        const float valueOriginX = leftMargin;
        NSString* valueText = [NSString stringWithFormat:@"%d%%", valuePercentage];
        
        [self addLabelLayerWithText:valueText
                            originX:valueOriginX originY:originY
                              width:valueWidth height:valueHeight
                          alignment: kCAAlignmentRight];
        
        const float labelOriginX = (leftMargin + valueWidth + labelMarginX);
        
        [self addLabelLayerWithText: [label capitalizedString]
                            originX: labelOriginX originY: originY
                              width: labelWidth height: labelHeight
                          alignment:kCAAlignmentLeft];
        
        if ((labelCount == 0) && (value > 0.5f))
        {
            [self speak: [label capitalizedString]];
        }
        
        labelCount += 1;
        if (labelCount > 4)
        {
            break;
        }
    }
}

- (void)setPredictionText: (NSString*) text withDuration: (float) duration
{
    if (duration > 0.0)
    {
        CABasicAnimation *colorAnimation = [CABasicAnimation animationWithKeyPath:@"foregroundColor"];
        colorAnimation.duration = duration;
        colorAnimation.fillMode = kCAFillModeForwards;
        colorAnimation.removedOnCompletion = NO;
        colorAnimation.fromValue = (id)[UIColor darkGrayColor].CGColor;
        colorAnimation.toValue = (id)[UIColor whiteColor].CGColor;
        colorAnimation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [self.predictionTextLayer addAnimation:colorAnimation forKey:@"colorAnimation"];
    }
    else
    {
        self.predictionTextLayer.foregroundColor = [UIColor whiteColor].CGColor;
    }
    
    [self.predictionTextLayer removeFromSuperlayer];
    [[self.view layer] addSublayer: self.predictionTextLayer];
    [self.predictionTextLayer setString: text];
}

- (void)triggerNextState
{
    switch (predictionState)
    {
        case eWaiting:
        {
            [self startPositiveLearning];
        } break;
            
        case ePositiveLearning:
        {
            [self startNegativeWaiting];
        } break;
            
        case eNegativeWaiting:
        {
            [self startNegativeLearning];
        } break;
            
        case eNegativeLearning:
        {
            [self startPredicting];
        } break;
            
        case ePredicting:
        {
            [self restartLearning];
        } break;
            
        default:
        {
            assert(FALSE); // Should never get here
        } break;
    }
}

- (void)handleNetworkPredictions: (float*) predictions withLength: (int) predictionsLength
{
    switch (predictionState)
    {
        case eWaiting:
        {
            // Do nothing
        } break;
            
        case ePositiveLearning:
        {
            jpcnn_train(trainer, 1.0f, predictions, predictionsLength);
            positivePredictionsCount += 1;
            if (positivePredictionsCount >= kPositivePredictionTotal)
            {
                [self triggerNextState];
            }
        } break;
            
        case eNegativeWaiting:
        {
            // Do nothing
        } break;
            
        case eNegativeLearning:
        {
            jpcnn_train(trainer, 0.0f, predictions, predictionsLength);
            negativePredictionsCount += 1;
            if (negativePredictionsCount >= kNegativePredictionTotal)
            {
                [self triggerNextState];
            }
        } break;
            
        case ePredicting:
        {
            const float predictionValue = jpcnn_predict(predictor, predictions, predictionsLength);
            NSLog(@"here1");
            [self setProgress: predictionValue];
            const float frameDuration = - [self.lastFrameTime timeIntervalSinceNow];
            self.lastFrameTime = [NSDate date];
            const float pingProgress = (predictionValue * frameDuration);
            timeToNextPing -= pingProgress;
            if (timeToNextPing < 0.0f) {
                AudioServicesPlaySystemSound(self.soundFileObject);
                timeToNextPing = kMinSecondsBetweenPings;
            }
        } break;
            
        default: {
            assert(FALSE); // Should never get here
        } break;
    }
    
    [self updateInfoDisplay];
}

- (void)setProgress: (float) amount
{
    const CGRect progressBackgroundBounds = [self.progressBackground frame];
    
    const float fullWidth = progressBackgroundBounds.size.width;
    const float foregroundWidth = (fullWidth * amount);
    
    CGRect progressForegroundBounds = [self.progressForeground frame];
    progressForegroundBounds.size.width = foregroundWidth;
    [self.progressForeground setFrame: progressForegroundBounds];
}

- (void) updateInfoDisplay
{
    switch (predictionState)
    {
        case eWaiting:
        {
            [self setInfo: @"When you're ready to teach me, press the button at the bottom and point your phone at the thing you want to recognize."];
            NSLog(@"here2");
            [self setProgress: 0.0f];
        } break;
            
        case ePositiveLearning:
        {
            [self setInfo: @"Move around the thing you want to recognize, keeping the phone pointed at it, to capture different angles."];
            NSLog(@"here3");
            [self setProgress: (positivePredictionsCount / (float)kPositivePredictionTotal)];
        } break;
            
        case eNegativeWaiting:
        {
            [self setInfo: @"Now I need to see examples of things that aren't the object you're looking for. Press the button when you're ready."];
            NSLog(@"here4");
            [self setProgress: 0.0f];
            [actionButton setTitle: @"Continue Teaching" forState:UIControlStateNormal];
        } break;
            
        case eNegativeLearning:
        {
            [self setInfo: @"Now move around the room pointing your phone at lots of things that are not the object you want to recognize."];
            NSLog(@"here5");
            [self setProgress: (negativePredictionsCount / (float)kNegativePredictionTotal)];
        } break;
            
        case ePredicting:
        {
            [self setInfo: @"You've taught the neural network to see! Now you should be able to scan around using the camera and detect the object's presence."];
            [actionButton setTitle: @"Teach Again" forState:UIControlStateNormal];
        } break;
            
        default:
        {
            assert(FALSE); // Should never get here
        } break;
    }
}

- (void) setInfo: (NSString*) info
{
    if (![info isEqualToString: lastInfo])
    {
        [self.infoForeground setString: info];
        [self speak: info];
        lastInfo = info;
    }
}

- (void) startPositiveLearning
{
    if (trainer != NULL)
    {
        jpcnn_destroy_trainer(trainer);
    }
    trainer = jpcnn_create_trainer();
    
    positivePredictionsCount = 0;
    predictionState = ePositiveLearning;
    
    [self updateInfoDisplay];
}

- (void) startNegativeWaiting
{
    predictionState = eNegativeWaiting;
    [self updateInfoDisplay];
}

- (void) startNegativeLearning
{
    negativePredictionsCount = 0;
    predictionState = eNegativeLearning;
    
    [self updateInfoDisplay];
}

- (void) startPredicting
{
    if (predictor != NULL)
    {
        jpcnn_destroy_predictor(predictor);
    }
    predictor = jpcnn_create_predictor_from_trainer(trainer);
//    fprintf(stderr, "------------- SVM File output - copy lines below ------------\n");
//    jpcnn_print_predictor(predictor);
//    fprintf(stderr, "------------- end of SVM File output - copy lines above ------------\n");
    predictionState = ePredicting;
    
    [self updateInfoDisplay];
    
    self.lastFrameTime = [NSDate date];
}

- (void) restartLearning
{
    [self startPositiveLearning];
}

- (void) speak: (NSString*) words
{
    if ([synth isSpeaking])
    {
        return;
    }
    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString: words];
    utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
    utterance.rate = 0.50*AVSpeechUtteranceDefaultSpeechRate;
    [synth speakUtterance:utterance];
}

@end
