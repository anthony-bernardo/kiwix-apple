//
//  ZimFileService.mm
//  Kiwix
//
//  Created by Chris Li on 8/17/17.
//  Copyright © 2017-2022 Chris Li. All rights reserved.
//

#include <unordered_map>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#include "kiwix/book.h"
#include "kiwix/kiwix_config.h"
#include "zim/archive.h"
#include "zim/entry.h"
#include "zim/error.h"
#include "zim/item.h"
#pragma clang diagnostic pop

#import "ZimFileService.h"
#import "ZimFileMetaData.h"

@interface ZimFileService ()

@property (assign) std::unordered_map<std::string, zim::Archive> *archives;
@property (strong) NSMutableDictionary *fileURLs; // [NSUUID: URL]

@end

@implementation ZimFileService

#pragma mark - init

- (instancetype)init {
    self = [super init];
    if (self) {
        self.archives = new std::unordered_map<std::string, zim::Archive>();
        self.fileURLs = [[NSMutableDictionary alloc] init];
        self.libzimVersion = [[NSString alloc] initWithUTF8String:LIBZIM_VERSION];
        self.libkiwixVersion = [[NSString alloc] initWithUTF8String:LIBKIWIX_VERSION];
    }
    return self;
}

+ (ZimFileService *)sharedInstance {
    static ZimFileService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ZimFileService alloc] init];
    });
    return sharedInstance;
}

- (void)dealloc {
    delete self.archives;
    for (NSUUID *zimFileID in self.fileURLs) {
        [self.fileURLs[zimFileID] stopAccessingSecurityScopedResource];
    }
}

#pragma mark - Reader Management

- (void)open:(NSURL *)url {
    try {
        // if url does not ends with "zim", skip it
        NSString *pathExtension = [[url pathExtension] lowercaseString];
        if (![pathExtension isEqualToString:@"zim"]) {
            return;
        }
        
        // if we have previously added this url, skip it
        if ([[self.fileURLs allKeysForObject:url] count] > 0) {
            return;
        }

        // add the archive
        [url startAccessingSecurityScopedResource];
        zim::Archive archive = zim::Archive([url fileSystemRepresentation]);
        self.archives->insert(std::make_pair(std::string(archive.getUuid()), archive));
        
        // store file URL
        NSUUID *zimFileID = [[NSUUID alloc] initWithUUIDBytes:(unsigned char *)archive.getUuid().data];
        self.fileURLs[zimFileID] = url;
    } catch (std::exception) {
        NSLog(@"Error opening zim file.");
    }
}

- (void)close:(NSUUID *)zimFileID {
    self.archives->erase([[[zimFileID UUIDString] lowercaseString] cStringUsingEncoding:NSUTF8StringEncoding]);
    [self.fileURLs[zimFileID] stopAccessingSecurityScopedResource];
    [self.fileURLs removeObjectForKey:zimFileID];
}

- (NSArray *)getReaderIdentifiers {
    return [self.fileURLs allKeys];
}

- (nonnull void *) getArchives {
    return self.archives;
}

# pragma mark - Metadata

- (ZimFileMetaData *)getMetaData:(NSUUID *)zimFileID {
    std::string zimFileID_C = [[[zimFileID UUIDString] lowercaseString] cStringUsingEncoding:NSUTF8StringEncoding];
    auto found = self.archives->find(zimFileID_C);
    if (found == self.archives->end()) {
        return nil;
    } else {
        kiwix::Book book = kiwix::Book();
        book.update(found->second);
        return [[ZimFileMetaData alloc] initWithBook: &book];
    }
}

- (NSData *)getFavicon:(NSUUID *)zimFileID {
    std::string zimFileID_C = [[[zimFileID UUIDString] lowercaseString] cStringUsingEncoding:NSUTF8StringEncoding];
        auto found = self.archives->find(zimFileID_C);
        if (found == self.archives->end()) {
            return nil;
        } else {
            try {
                zim::Blob blob = found->second.getIllustrationItem().getData();
                return [NSData dataWithBytes:blob.data() length:blob.size()];
            } catch (std::exception) {
                return nil;
            }
        }
}

+ (ZimFileMetaData *)getMetaDataWithFileURL:(NSURL *)url {
    ZimFileMetaData *metaData = nil;
    [url startAccessingSecurityScopedResource];
    try {
        kiwix::Book book = kiwix::Book();
        book.update(zim::Archive([url fileSystemRepresentation]));
        metaData = [[ZimFileMetaData alloc] initWithBook: &book];
    } catch (std::exception e) { }
    [url stopAccessingSecurityScopedResource];
    return metaData;
}

# pragma mark - URL Handling

- (NSURL *)getFileURL:(NSUUID *)zimFileID {
    return self.fileURLs[zimFileID];
}

- (NSString *_Nullable)getRedirectedPath:(NSUUID *_Nonnull)zimFileID contentPath:(NSString *_Nonnull)contentPath {
    std::string zimFileID_C = [[[zimFileID UUIDString] lowercaseString] cStringUsingEncoding:NSUTF8StringEncoding];
    auto found = self.archives->find(zimFileID_C);
    if (found == self.archives->end()) {
        return nil;
    }
    try {
        std::string contentPathC = [contentPath cStringUsingEncoding:NSUTF8StringEncoding];
        zim::Item item = found->second.getEntryByPath(contentPathC).getRedirect();
        return [NSString stringWithUTF8String:item.getPath().c_str()];
    } catch (std::exception) {
        return nil;
    }
}

- (NSString *)getMainPagePath:(NSUUID *)zimFileID {
    std::string zimFileID_C = [[[zimFileID UUIDString] lowercaseString] cStringUsingEncoding:NSUTF8StringEncoding];
    auto found = self.archives->find(zimFileID_C);
    if (found == self.archives->end()) {
        return nil;
    }
    try {
        zim::Entry entry = found->second.getMainEntry();
        zim::Item item = entry.getItem(entry.isRedirect());
        return [NSString stringWithCString:item.getPath().c_str() encoding:NSUTF8StringEncoding];
    } catch (std::exception) {
        return nil;
    }
}

- (NSString *)getRandomPagePath:(NSUUID *)zimFileID {
    std::string zimFileID_C = [[[zimFileID UUIDString] lowercaseString] cStringUsingEncoding:NSUTF8StringEncoding];
    auto found = self.archives->find(zimFileID_C);
    if (found == self.archives->end()) {
        return nil;
    }
    try {
        zim::Entry entry = found->second.getRandomEntry();
        zim::Item item = entry.getItem(entry.isRedirect());
        return [NSString stringWithCString:item.getPath().c_str() encoding:NSUTF8StringEncoding];
    } catch (std::exception) {
        return nil;
    }
}

- (NSDictionary *)getContent:(NSUUID *)zimFileID contentPath:(NSString *)contentPath
                  start:(NSUInteger)start end:(NSUInteger)end {
    if ([contentPath hasPrefix:@"/"]) {
        contentPath = [contentPath substringFromIndex:1];
    }
    
    std::string zimFileID_C = [[[zimFileID UUIDString] lowercaseString] cStringUsingEncoding:NSUTF8StringEncoding];
    auto found = self.archives->find(zimFileID_C);
    if (found == self.archives->end()) {
        return nil;
    }
    try {
        zim::Entry entry = found->second.getEntryByPath([contentPath cStringUsingEncoding:NSUTF8StringEncoding]);
        zim::Item item = entry.getItem(entry.isRedirect());
        zim::Blob blob;
        if (start == 0 && end == 0) {
            blob = item.getData();
        } else if (end == 0) {
            blob = item.getData(start, item.getSize() - start);
        } else {
            blob = item.getData(start, fmin(item.getSize() - start, end - start + 1));
        }
        return @{
            @"data": [NSData dataWithBytes:item.getData().data() length:blob.size()],
            @"mime": [NSString stringWithUTF8String:item.getMimetype().c_str()],
            @"start": [NSNumber numberWithUnsignedLongLong:start],
            @"end": [NSNumber numberWithUnsignedLongLong:start + blob.size() - 1],
            @"size": [NSNumber numberWithUnsignedLongLong:item.getSize()]
        };
    } catch (std::exception) {
        return nil;
    }
}

@end
