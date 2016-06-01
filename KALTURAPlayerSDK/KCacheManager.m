//
//  KCacheManager.m
//  KALTURAPlayerSDK
//
//  Created by Nissim Pardo on 8/23/15.
//  Copyright (c) 2015 Kaltura. All rights reserved.
//

#import "KCacheManager.h"
#import "NSString+Utilities.h"
#import "KPLog.h"
#import "NSMutableDictionary+Cache.h"

NSString *const CacheDirectory = @"KalturaPlayerCache";

#define MB (1024*1024)
#define GB (MB*1024)

@interface KCacheManager ()
@property (nonatomic, readonly) NSString *cachePath;

@property (strong, nonatomic, readonly) NSBundle *bundle;
@property (strong, nonatomic, readonly) NSDictionary *cacheConditions;
@end

@interface NSString (Cache)
@property (nonatomic, readonly) BOOL deleteFile;
@property (nonatomic, readonly) NSString *pathForFile;
@end

//#define LOG_CACHE_EVENTS
#ifdef LOG_CACHE_EVENTS
static void cacheHit(NSString* url) {
    NSLog(@"CACHE HIT: %@", url);
}

static void cacheMiss(NSString* url) {
    NSLog(@"CACHE MISS: %@", url);
}

static void cacheSave(NSString* url) {
    NSLog(@"CACHE SAVE: %@", url);
}

static void cacheWillSave(NSString* url) {
    NSLog(@"CACHE willSAVE: %@", url);
}

static void cacheRemove(NSString* url) {
    NSLog(@"CACHE REM: %@", url);
}
#else
#define cacheHit(x)
#define cacheMiss(x)
#define cacheSave(x)
#define cacheWillSave(x)
#define cacheRemove(x)
#endif

@implementation KCacheManager
@synthesize cachePath = _cachePath;
@synthesize bundle = _bundle, cacheConditions = _cacheConditions, withDomain = _withDomain, subStrings = _subStrings, offlineSubStr = _offlineSubStr;

+ (KCacheManager *)shared {
    KPLogTrace(@"Enter");
    static KCacheManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    
    KPLogTrace(@"Exit");
    return instance;
}

// The SDK's bundle
- (NSBundle *)bundle {
    KPLogTrace(@"Enter");
    if (!_bundle) {
        NSURL* bundleURL = [[NSBundle bundleForClass:self.classForCoder]
                            URLForResource:@"KALTURAPlayerSDKResources"
                            withExtension:@"bundle"];
                
        NSAssert(bundleURL, @"KALTURAPlayerSDKResources.bundle is not found, can't continue");
        
        _bundle = [NSBundle bundleWithURL:bundleURL];
    }
    
    KPLogTrace(@"Exit");
    return _bundle;
}

- (void)setBaseURL:(NSString *)host {
    KPLogTrace(@"Enter");
    _baseURL = [host stringByReplacingOccurrencesOfString:[host lastPathComponent] withString:@""];
    KPLogTrace(@"Exit");
}


// Fetches the White list urls
- (NSDictionary *)cacheConditions {
    KPLogTrace(@"Enter");
    if (!_cacheConditions) {
        NSString *path = [self.bundle pathForResource:@"CachedStrings" ofType:@"plist"];
        _cacheConditions = [NSDictionary dictionaryWithContentsOfFile:path];
    }
    
    KPLogTrace(@"Exit");
    return _cacheConditions;
}

// The url list which have to be checked by the domain first
- (NSDictionary *)withDomain {
    KPLogTrace(@"Enter");
    if (!_withDomain) {
        _withDomain = self.cacheConditions[@"withDomain"];
    }
    
    KPLogTrace(@"Exit");
    return _withDomain;
}


// The url list which should contain substring fron the White list
- (NSDictionary *)subStrings {
    KPLogTrace(@"Enter");
    if (!_subStrings) {
        _subStrings = self.cacheConditions[@"substrings"];
    }
    
    KPLogTrace(@"Exit");
    return _subStrings;
}

// The url list which should contain substring fron the White list in
// When there is no network
- (NSDictionary *)offlineSubStr {
    KPLogTrace(@"Enter");
    if (!_offlineSubStr) {
        _offlineSubStr = self.cacheConditions[@"offlineSubStr"];
    }
    
    KPLogTrace(@"Exit");
    return _offlineSubStr;
}


// Lazy initialization of the cache folder path
- (NSString *)cachePath {
    KPLogTrace(@"Enter");
    if (!_cachePath) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES); // Get documents folder
        _cachePath = [paths.firstObject stringByAppendingPathComponent:CacheDirectory];
    }
    
    KPLogTrace(@"Exit");
    return _cachePath;
}


// Calculates the size of the cached files
- (float)cachedSize {
    KPLogTrace(@"Enter");
    long long fileSize = 0;
    NSArray *files = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:self.cachePath error:nil];
    for (NSString *file in files) {
        fileSize += [[[NSFileManager defaultManager] attributesOfItemAtPath:file.pathForFile error:nil][NSFileSize] integerValue];
    }
    
    KPLogTrace(@"Exit");
    return (float)fileSize / MB;
}


// Returns sorted array of the content of the cache folder
- (NSArray *)files {
    KPLogTrace(@"Enter");
    NSMutableArray *files = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath:self.cachePath error:nil].mutableCopy;
    [files sortUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        NSDate* d1 = [[NSFileManager defaultManager] attributesOfItemAtPath:obj1.pathForFile error:nil][NSFileModificationDate];
        NSDate* d2 = [[NSFileManager defaultManager] attributesOfItemAtPath:obj2.pathForFile error:nil][NSFileModificationDate];
        return [d1 compare:d2];
    }];
    
    KPLogTrace(@"Exit");
    return files;
}

@end

@implementation NSString (Cache)

// returns the full path for a file name
- (NSString *)pathForFile {
    KPLogTrace(@"Enter");
    KPLogTrace(@"Exit");
    return [CacheManager.cachePath stringByAppendingPathComponent:self];
}

// Unarchive the stored headers
- (NSDictionary *)cachedResponseHeaders {
    KPLogTrace(@"Enter");
    NSString *contentId = self.extractLocalContentId;
    NSString *path = self.md5.appendPath;
    if (contentId.length) {
        path = [contentId appendPath];
    }
    
    NSString *pathForHeaders = [path stringByAppendingPathComponent:@"headers"];
    NSData *data = [[NSFileManager defaultManager] contentsAtPath:pathForHeaders];
    
    if (data) {
        cacheHit(self);
        [self setDateAttributeAtPath:pathForHeaders];
        NSDictionary *cached = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        
        KPLogTrace(@"Exit");
        return cached;
    } else {
        cacheMiss(self);
        KPLogTrace(@"Exit");
        return nil;
    }    
}

// Fetches the page content from the file system
- (NSData *)cachedPage {
    KPLogTrace(@"Enter");
    NSString *contentId = self.extractLocalContentId;
    NSString *path = self.md5.appendPath;
    
    if (contentId) {
        path = contentId.appendPath;
    }
    
    NSString *pathForData = [path stringByAppendingPathComponent:@"data"];
    NSData *data = [[NSFileManager defaultManager] contentsAtPath:pathForData];
    
    if (data) {
        [self setDateAttributeAtPath:pathForData];
    }
    
    KPLogTrace(@"Exit");
    return data;
}



- (void)setDateAttributeAtPath: (NSString *)path {
    KPLogTrace(@"Enter");
    NSError *err = nil;
    [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: [NSDate date]} ofItemAtPath:path error:&err];
    
    if (err) {
        KPLogError(err.localizedDescription);
    }
    
    KPLogTrace(@"Exit");
}

- (NSString *)appendPath {
    KPLogTrace(@"Enter");
    KPLogTrace(@"Exit");
    return [CacheManager.cachePath stringByAppendingPathComponent:self];
}


/**
 Deletes file by name
 @return BOOL YES if the file deleted succesfully
 */
- (BOOL)deleteFile {
    KPLogTrace(@"Enter");
    cacheRemove(self);
    NSString *path = self.pathForFile;
    if ([[NSFileManager defaultManager] isDeletableFileAtPath:path]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:path
                                                   error:&error];
        if (!error) {
            KPLogTrace(@"Exit");
            return YES;
        } else {
            KPLogError(@"%@", error);
        }
    }
    
    KPLogTrace(@"Exit");
    return NO;
}

@end

@implementation CachedURLParams

- (long long)freeDiskSpace {
    KPLogTrace(@"Enter");
    KPLogTrace(@"Exit");
    return [[[[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil] objectForKey:NSFileSystemFreeSize] longLongValue];
}

-(void)raise:(NSString*)error {
    [NSException raise:@"Error" format:@"%@", error];
}

- (void)storeCacheResponse {
    KPLogTrace(@"Enter");
    float cachedSize = CacheManager.cachedSize;
    
    // if the cache size is too big, erases the least used files
    if (cachedSize > ((float)[self freeDiskSpace] / MB) ||
        cachedSize > CacheManager.maxCacheSize) {
        float overflowSize = cachedSize - CacheManager.maxCacheSize + (float)self.data.length / MB;
        NSArray *files = CacheManager.files;
        for (NSString *fileName in files) {
            if (overflowSize > 0) {
                NSDictionary *fileDictionary = [[NSFileManager defaultManager] attributesOfItemAtPath:[CacheManager.cachePath stringByAppendingPathComponent:fileName]
                                                                                                error:nil];
                if (fileName.deleteFile) {
                    overflowSize -= [fileDictionary fileSize];
                }
            } else {
                break;
            }
        }
    }
    

    NSError *error = nil;
    @try {
        // Create Kaltura's folder if not already exists
        NSString *pageFolderPath = self.url.absoluteString.md5.appendPath;
        if (self.url.absoluteString.extractLocalContentId) {
            pageFolderPath = self.url.absoluteString.extractLocalContentId.appendPath;
        }

        if (![[NSFileManager defaultManager] createDirectoryAtPath:pageFolderPath
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error]) {
            [self raise:@"Failed to create pageFolderPath"];
        }
        
        // Store the page
        cacheWillSave(self.url.absoluteString);
        NSMutableDictionary *attributes = [NSMutableDictionary new];
        attributes.allHeaderFields = self.response.allHeaderFields;
        attributes.statusCode = self.response.statusCode;
        NSString *pathForHeaders = [pageFolderPath stringByAppendingPathComponent:@"headers"];
        NSString *pathForData = [pageFolderPath stringByAppendingPathComponent:@"data"];
        
        NSData* headersArchive = [NSKeyedArchiver archivedDataWithRootObject:attributes];
        
        if (![headersArchive writeToFile:pathForHeaders options:NSDataWritingAtomic error:&error]) {
            [self raise:@"Failed to store response headers"];
        }
            
        if (![self.data writeToFile:pathForData options:NSDataWritingAtomic error:&error]) {
            [self raise:@"Failed to store response data"];
        }
        cacheSave(self.url.absoluteString);

    } @catch (NSException *exception) {
        KPLogError(@"%@ (%@)", [exception reason], error);
    }
    
    KPLogTrace(@"Exit");
}

- (NSMutableData *)data {
    KPLogTrace(@"Enter");
    if (!_data) {
        _data = [[NSMutableData alloc] init];
    }
    
    KPLogTrace(@"Exit");
    return _data;
}

@end