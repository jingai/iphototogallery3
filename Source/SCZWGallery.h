//
// Copyright (c) Zach Wily
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without modification, 
// are permitted provided that the following conditions are met:
// 
// - Redistributions of source code must retain the above copyright notice, this 
//     list of conditions and the following disclaimer.
// 
// - Redistributions in binary form must reproduce the above copyright notice, this
//     list of conditions and the following disclaimer in the documentation and/or 
//     other materials provided with the distribution.
// 
// - Neither the name of Zach Wily nor the names of its contributors may be used to 
//     endorse or promote products derived from this software without specific prior 
//     written permission.
// 
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR 
//  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES 
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
//   LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON 
//  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import <Foundation/Foundation.h>

@class SCZWGalleryAlbum;
@class SCZWURLConnection;

typedef enum
{
    GR_STAT_SUCCESS = 0,                       // The command the client sent in the request completed successfully. The data (if any) in the response should be considered valid.    
    GR_STAT_PROTO_MAJ_VER_INVAL = 101,         // The protocol major version the client is using is not supported.
    GR_STAT_PROTO_MIN_VER_INVAL = 102,         // The protocol minor version the client is using is not supported.    
    GR_STAT_PROTO_VER_FMT_INVAL = 103,         // The format of the protocol version string the client sent in the request is invalid.    
    GR_STAT_PROTO_VER_MISSING = 104,           // The request did not contain the required protocol_version key.
    GR_STAT_PASSWD_WRONG = 201,                // The password and/or username the client send in the request is invalid.
    GR_STAT_LOGIN_MISSING = 202,               // The client used the login command in the request but failed to include either the username or password (or both) in the request.
    GR_STAT_UNKNOWN_CMD = 301,                 // The value of the cmd key is not valid.    
    GR_STAT_NO_ADD_PERMISSION = 401,           // The user does not have permission to add an item to the gallery.
    GR_STAT_NO_FILENAME = 402,                 // No filename was specified.
    GR_STAT_UPLOAD_PHOTO_FAIL = 403,           // The file was received, but could not be processed or added to the album.
    GR_STAT_NO_WRITE_PERMISSION = 404,         // No write permission to destination album.
    GR_STAT_NO_CREATE_ALBUM_PERMISSION = 501,  // A new album could not be created because the user does not have permission to do so.
    GR_STAT_CREATE_ALBUM_FAILED = 502,         // A new album could not be created, for a different reason (name conflict).
    SCZW_GALLERY_COULD_NOT_CONNECT = 1000,       // Could not connect to the gallery
    SCZW_GALLERY_PROTOCOL_ERROR = 1001,          // Something went wrong with the protocol (no status sent, couldn't decode, etc)
    SCZW_GALLERY_UNKNOWN_ERROR = 1002,
    SCZW_GALLERY_OPERATION_DID_CANCEL = 1003     // The user cancelled whatever operation was happening
} SCZWGalleryRemoteStatusCode;

typedef enum
{
    GalleryTypeG1 = 0,
    GalleryTypeG2,
    GalleryTypeG2XMLRPC
} SCZWGalleryType;

@interface SCZWGallery : NSObject {
    NSURL* url;
    NSURL* fullURL;
    NSString* requestkey;
    NSString* username;
    NSString* password;
    SCZWGalleryType type;
    
    BOOL loggedIn;
    int majorVersion;
    int minorVersion;
    NSArray* albums;
    NSMutableArray* jsonalbums;
    BOOL tagsActivated;
	NSMutableDictionary* tags;
    NSString *lastCreatedAlbumName;
    
    NSStringEncoding sniffedEncoding;
    
    id delegate;    
    SCZWURLConnection *currentConnection;
}

- (id)init;
- (id)initWithURL:(NSURL *)url username:(NSString *)username;
- (id)initWithDictionary:(NSDictionary *)description;
+ (SCZWGallery *)galleryWithURL:(NSURL *)url username:(NSString *)username;
+ (SCZWGallery *)galleryWithDictionary:(NSDictionary *)description;

- (void)cancelOperation;
- (void)login;
- (void)logout;
- (void)createAlbumWithName:(NSString *)name title:(NSString *)title summary:(NSString *)summary parent:(SCZWGallery *)parent;
- (void)getAlbums;
- (SCZWGalleryRemoteStatusCode)doCreateTagWithName:(NSString *)name;
- (SCZWGalleryRemoteStatusCode)doLinkTag:(NSString *)tagUrl withPhoto:(NSString *)photoUrl;

// accessor methods
- (NSURL *)url;
- (NSURL *)fullURL;
- (NSString *)identifier;
- (NSString *)urlString;
- (NSString *)requestkey;
- (NSString *)username;
- (int)majorVersion;
- (int)minorVersion;
- (BOOL)loggedIn;
- (NSArray *)albums;
- (NSDictionary *)infoDictionary;
- (SCZWGalleryType)type;
- (BOOL)isGalleryV2;
- (void)setDelegate:(id)delegate;
- (id)delegate;
- (void)setPassword:(NSString *)password;
- (NSString *)lastCreatedAlbumName;
- (NSStringEncoding)sniffedEncoding;
- (BOOL)tagsActivated;
- (NSMutableDictionary*)tags;

// This helper method can be used by children too
- (id)parseResponseData:(NSData*)responseData;
- (NSMutableDictionary *) getGalleryTags; 
- (NSDictionary *) doGetItem:(NSURL*)itemUrl;
- (SCZWGalleryRemoteStatusCode)getandparseAlbums:(NSArray*)member;
- (NSString *)formNameWithName:(NSString *)paramName;

@end

@interface SCZWGallery (SCZWGalleryDelegateMethods)

- (void)galleryDidLogin:(SCZWGallery *)sender;
- (void)gallery:(SCZWGallery *)sender loginFailedWithCode:(SCZWGalleryRemoteStatusCode)status;

- (void)galleryDidGetAlbums:(SCZWGallery *)sender;
- (void)gallery:(SCZWGallery *)sender getAlbumsFailedWithCode:(SCZWGalleryRemoteStatusCode)status;

- (void)galleryDidCreateAlbum:(SCZWGallery *)sender;
- (void)gallery:(SCZWGallery *)sender createAlbumFailedWithCode:(SCZWGalleryRemoteStatusCode)status;

@end
