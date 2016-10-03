//
// Copyright 2011-2014 NimbusKit
//
// Forked from Three20 June 15, 2011 - Copyright 2009-2011 Facebook
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "NINetworkImageView.h"

#import "NimbusCore.h"
#import "AFNetworking.h"
#import "NIImageProcessing.h"
#import "NIImageResponseSerializer.h"
#import <objc/runtime.h>

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "Nimbus requires ARC support."
#endif


@interface NSObject (NSURLSessionDataTask)
@property (strong, nullable)  NSDictionary * userInfo;
@end

@implementation NSObject (BSYSyncManager)
	
	static void* userInfoKey = "userInfo";
	-(void) setUserInfo:(id)value
	{
		value = ^(id v){ return v; }(value);
		objc_AssociationPolicy policy = [value conformsToProtocol:@protocol(NSCopying)] ? OBJC_ASSOCIATION_COPY : OBJC_ASSOCIATION_RETAIN;
		
		@synchronized(self)
		{
			{
				SEL __checkSel = NSSelectorFromString(@"willChangeValueForKey:");
				if ([self respondsToSelector:__checkSel])
				{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
					[self performSelector:__checkSel withObject:@"userInfo"];
#pragma clang diagnostic pop
				}
			}
			
			objc_setAssociatedObject(self, userInfoKey, value, policy);
			
			{
				SEL __checkSel = NSSelectorFromString(@"didChangeValueForKey:");
				if ([self respondsToSelector:__checkSel])
				{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
					[self performSelector:__checkSel withObject:@"userInfo"];
#pragma clang diagnostic pop
				}
			};
		}
	}
	
	-(id) userInfo
	{
		id value = ((void*)0);
		
		@synchronized(self)
		{
			value = objc_getAssociatedObject(self, userInfoKey);
		};
		
		return ^(id v){ return v; }(value);
	}
@end

@interface NINetworkImageView()
@property (nonatomic, strong) NSURLSessionTask *task;
@end


@implementation NINetworkImageView



- (void)cancelOperation {
  [self.task cancel];
  self.task = nil;
}

- (void)dealloc {
  [self cancelOperation];
}

- (void)assignDefaults {
  self.sizeForDisplay = YES;
  self.scaleOptions = NINetworkImageViewScaleToFitLeavesExcessAndScaleToFillCropsExcess;
  self.interpolationQuality = kCGInterpolationDefault;

  self.imageMemoryCache = [Nimbus imageMemoryCache];
}

- (id)initWithImage:(UIImage *)image {
  if ((self = [super initWithImage:image])) {
    [self assignDefaults];

    // Retain the initial image.
    self.initialImage = image;
  }
  return self;
}

- (id)initWithFrame:(CGRect)frame {
  if ((self = [self initWithImage:nil])) {
    self.frame = frame;
  }
  return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
  if ((self = [super initWithCoder:aDecoder])) {
    if (nil != self.image) {
      self.initialImage = self.image;
    }
    [self assignDefaults];
  }
  return self;
}

- (id)init {
  return [self initWithImage:nil];
}

- (NSString *)cacheKeyForCacheIdentifier:(NSString *)cacheIdentifier
                               imageSize:(CGSize)imageSize
                                cropRect:(CGRect)cropRect
                             contentMode:(UIViewContentMode)contentMode
                            scaleOptions:(NINetworkImageViewScaleOptions)scaleOptions {
  NIDASSERT(NIIsStringWithAnyText(cacheIdentifier));

  NSString* cacheKey = cacheIdentifier;

  // Append the size to the key. This allows us to differentiate cache keys by image dimension.
  // If the display size ever changes, we want to ensure that we're fetching the correct image
  // from the cache.
  if (self.sizeForDisplay) {
    cacheKey = [cacheKey stringByAppendingFormat:@"%@%@{%@,%@}",
                NSStringFromCGSize(imageSize), NSStringFromCGRect(cropRect), [@(contentMode) stringValue], [@(scaleOptions) stringValue]];
  }

  // The resulting cache key will look like:
  // /path/to/image({width,height}{contentMode,cropImageForDisplay})

  return cacheKey;
}

- (NSDate *)expirationDate {
  return (self.maxAge != 0) ? [NSDate dateWithTimeIntervalSinceNow:self.maxAge] : nil;
}

#pragma mark - Internal consistent implementation of state changes


- (void)_didStartLoading {
  if ([self.delegate respondsToSelector:@selector(networkImageViewDidStartLoad:)]) {
    [self.delegate networkImageViewDidStartLoad:self];
  }

  [self networkImageViewDidStartLoading];
}

- (void)_didFinishLoadingWithImage:(UIImage *)image
                   cacheIdentifier:(NSString *)cacheIdentifier
                       displaySize:(CGSize)displaySize
                          cropRect:(CGRect)cropRect
                       contentMode:(UIViewContentMode)contentMode
                      scaleOptions:(NINetworkImageViewScaleOptions)scaleOptions
                    expirationDate:(NSDate *)expirationDate {
  // Store the result image in the memory cache.
  if (nil != self.imageMemoryCache && nil != image) {
    NSString* cacheKey = [self cacheKeyForCacheIdentifier:cacheIdentifier
                                                imageSize:displaySize
                                                 cropRect:cropRect
                                              contentMode:contentMode
                                             scaleOptions:scaleOptions];

    // Store the image in the memory cache, possibly with an expiration date.
    [self.imageMemoryCache storeObject: image
                              withName: cacheKey
                          expiresAfter: expirationDate];
  }

  if (nil != image) {
    // Display the new image.
    [self setImage:image];

  } else {
    [self setImage:self.initialImage];
  }

  self.task = nil;

  if ([self.delegate respondsToSelector:@selector(networkImageView:didLoadImage:)]) {
    [self.delegate networkImageView:self didLoadImage:self.image];
  }

  [self networkImageViewDidLoadImage:image];
}

- (void)_didFailToLoadWithError:(NSError *)error {
  self.task = nil;

  if ([self.delegate respondsToSelector:@selector(networkImageView:didFailWithError:)]) {
    [self.delegate networkImageView:self didFailWithError:error];
  }

  [self networkImageViewDidFailWithError:error];
}

#pragma mark - Subclassing


- (void)networkImageViewDidStartLoading {
  // No-op. Meant to be overridden.
}

- (void)networkImageViewDidLoadImage:(UIImage *)image {
  // No-op. Meant to be overridden.
}

- (void)networkImageViewDidFailWithError:(NSError *)error {
  // No-op. Meant to be overridden.
}

#pragma mark - Public


- (void)setPathToNetworkImage:(NSString *)pathToNetworkImage {
  [self setPathToNetworkImage: pathToNetworkImage
               forDisplaySize: CGSizeZero
                  contentMode: self.contentMode
                     cropRect: CGRectZero];
}

- (void)setPathToNetworkImage:(NSString *)pathToNetworkImage forDisplaySize:(CGSize)displaySize {
  [self setPathToNetworkImage: pathToNetworkImage
               forDisplaySize: displaySize
                  contentMode: self.contentMode
                     cropRect: CGRectZero];
}

- (void)setPathToNetworkImage:(NSString *)pathToNetworkImage forDisplaySize:(CGSize)displaySize contentMode:(UIViewContentMode)contentMode {
  [self setPathToNetworkImage: pathToNetworkImage
               forDisplaySize: displaySize
                  contentMode: contentMode
                     cropRect: CGRectZero];
}

- (void)setPathToNetworkImage:(NSString *)pathToNetworkImage cropRect:(CGRect)cropRect {
  [self setPathToNetworkImage: pathToNetworkImage
               forDisplaySize: CGSizeZero
                  contentMode: self.contentMode
                     cropRect: cropRect];
}

- (void)setPathToNetworkImage:(NSString *)pathToNetworkImage contentMode:(UIViewContentMode)contentMode {
  [self setPathToNetworkImage: pathToNetworkImage
               forDisplaySize: CGSizeZero
                  contentMode: contentMode
                     cropRect: CGRectZero];
}

- (void)setPathToNetworkImage:(NSString *)pathToNetworkImage forDisplaySize:(CGSize)displaySize contentMode:(UIViewContentMode)contentMode cropRect:(CGRect)cropRect {
	[self cancelOperation];

	if (NIIsStringWithAnyText(pathToNetworkImage)) {
		NSURL* url = nil;

		// Check for file URLs.
		if ([pathToNetworkImage hasPrefix:@"/"]) {
		  // If the url starts with / then it's likely a file URL, so treat it accordingly.
		  url = [NSURL fileURLWithPath:pathToNetworkImage];

		} else {
		  // Otherwise we assume it's a regular URL.
		  url = [NSURL URLWithString:[pathToNetworkImage stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
		}

		// If the URL failed to be created, there's not much we can do here.
		if (nil == url) {
		  return;
		}
		// We explicitly do not allow negative display sizes. Check the call stack to figure
		// out who is providing a negative display size. It's possible that displaySize is an
		// uninitialized CGSize structure.
		NIDASSERT(displaySize.width >= 0);
		NIDASSERT(displaySize.height >= 0);
		
		// If an invalid display size IS provided, use the image view's frame instead.
		if (0 >= displaySize.width || 0 >= displaySize.height) {
		  displaySize = self.frame.size;
		}
		
		UIImage* image = nil;
		
		// Attempt to load the image from memory first.
		NSString* cacheKey = nil;
		if (nil != self.imageMemoryCache) {
		  cacheKey = [self cacheKeyForCacheIdentifier:pathToNetworkImage
											imageSize:displaySize
											 cropRect:cropRect
										  contentMode:contentMode
										 scaleOptions:self.scaleOptions];
		  image = [self.imageMemoryCache objectWithName:cacheKey];
		}

		if (nil != image) {
		  // We successfully loaded the image from memory.
		  [self setImage:image];
		  
		  if ([self.delegate respondsToSelector:@selector(networkImageView:didLoadImage:)]) {
			[self.delegate networkImageView:self didLoadImage:self.image];
		  }
		  
		  [self networkImageViewDidLoadImage:image];

		} else {
		  if (!self.sizeForDisplay) {
			displaySize = CGSizeZero;
			contentMode = UIViewContentModeScaleToFill;
		  }

		AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
			
		@synchronized (manager) {
		  NIImageResponseSerializer* serializer = [NIImageResponseSerializer serializer];
		  // We handle image scaling ourselves in the image processing method, so we need to disable
		  // AFNetworking from doing so as well.
		  serializer.imageScale = 1;
		  serializer.contentMode = contentMode;
		  serializer.cropRect = cropRect;
		  serializer.displaySize = displaySize;
		  serializer.scaleOptions = self.scaleOptions;
		  serializer.interpolationQuality = self.interpolationQuality;
			
		  manager.responseSerializer = [AFImageResponseSerializer serializer];

		  NSString* originalCacheKey = [self cacheKeyForCacheIdentifier:pathToNetworkImage
															  imageSize:displaySize
															   cropRect:cropRect
															contentMode:contentMode
														   scaleOptions:self.scaleOptions];
			
		  NSURLSessionDataTask* task = [manager GET:url.absoluteString parameters:nil
			progress:^(NSProgress * _Nonnull progres) {
				if ([self.delegate respondsToSelector:@selector(networkImageView:readBytes:totalBytes:)]) {
					[self.delegate networkImageView:self readBytes:progres.completedUnitCount totalBytes:progres.totalUnitCount];
				}
			}
										
			success:^(NSURLSessionTask *task, id responseObject) {
				NSString* blockCacheKey = [self cacheKeyForCacheIdentifier:pathToNetworkImage
												imageSize:displaySize
												cropRect:cropRect
												contentMode:contentMode
												scaleOptions:self.scaleOptions];

				// Only keep this result if it's for the most recent request.
				if ([blockCacheKey isEqualToString:task.userInfo[@"cacheKey"]]) {
					[self _didFinishLoadingWithImage:responseObject
							   cacheIdentifier:pathToNetworkImage
								   displaySize:displaySize
									  cropRect:cropRect
								   contentMode:contentMode
								  scaleOptions:self.scaleOptions
								expirationDate:[self expirationDate]];
				}

			}
			failure:^(NSURLSessionTask *operation, NSError *error) {
			 [self _didFailToLoadWithError:error];
		  }];

		  task.userInfo = @{@"cacheKey":originalCacheKey};
		  self.task = task;

		  [self _didStartLoading];
		}
	  }
	}
}

- (void)prepareForReuse {
  [self cancelOperation];

  [self setImage:self.initialImage];
}

#pragma mark - Properties


- (void)setInitialImage:(UIImage *)initialImage {
  if (_initialImage != initialImage) {
    // Only update the displayed image if we're currently showing the old initial image.
    BOOL updateDisplayedImage = (_initialImage == self.image);
    _initialImage = initialImage;

    if (updateDisplayedImage) {
      [self setImage:_initialImage];
    }
  }
}

- (BOOL)isLoading {
  return self.task.state == NSURLSessionTaskStateRunning;
}

@end

