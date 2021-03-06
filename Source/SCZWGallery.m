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

#import "json/JSON.h"
#import "SCZWGallery.h"
#import "SCZWGalleryAlbum.h"
#import "SCNSString+misc.h"
#import "SCZWURLConnection.h"
#import "SCInterThreadMessaging.h"
#import "SCZWMutableURLRequest.h"

@interface SCZWGallery (PrivateAPI)
- (void)loginThread:(NSDictionary *)threadDispatchInfo;
- (SCZWGalleryRemoteStatusCode)doLogin;

- (void)getAlbumsThread:(NSDictionary *)threadDispatchInfo;
- (SCZWGalleryRemoteStatusCode)doGetAlbums;

- (void)createAlbumThread:(NSDictionary *)threadDispatchInfo;
- (SCZWGalleryRemoteStatusCode)doCreateAlbumWithName:(NSString *)name title:(NSString *)title summary:(NSString *)summary parent:(SCZWGalleryAlbum *)parent;

- (SCZWGalleryRemoteStatusCode)doCreateTagWithName:(NSString *)name;

- (id)doCreateObjectWithData:(NSMutableDictionary *)dict  url:(NSString *)aurl;

- (SCZWGalleryRemoteStatusCode)doLinkTag:(NSString *)tagUrl withPhoto:(NSString *)photoUrl;

@end

@implementation SCZWGallery

#pragma mark Object Life Cycle

- (id)init {
    return self;
}

- (id)initWithURL:(NSURL*)newUrl username:(NSString*)newUsername {
	url = [newUrl retain];
    fullURL = [[NSURL alloc] initWithString:[[url absoluteString] stringByAppendingString:@"rest"]];
    username = [newUsername retain];
    delegate = self;
    loggedIn = FALSE;
    tagsActivated = FALSE;
    majorVersion = 0;
    minorVersion = 0;
    type = GalleryTypeG1;
    
    return self;
}

- (id)initWithDictionary:(NSDictionary*)dictionary {
    [self initWithURL:[NSURL URLWithString:[dictionary objectForKey:@"url"]] 
             username:[dictionary objectForKey:@"username"]];
    
    NSNumber *typeNumber = [dictionary objectForKey:@"type"];
    if (typeNumber)
        type = [typeNumber intValue];
    
    return self;
}

+ (SCZWGallery*)galleryWithURL:(NSURL*)newUrl username:(NSString*)newUsername {
    return [[[SCZWGallery alloc] initWithURL:newUrl username:newUsername] autorelease];
}

+ (SCZWGallery*)galleryWithDictionary:(NSDictionary*)dictionary {
    return [[[SCZWGallery alloc] initWithDictionary:dictionary] autorelease];
}

- (void)dealloc
{
    [url release];
    [requestkey release];
    [username release];
    [password release];
    [albums release];
    [jsonalbums release];
    [tags release];
    [lastCreatedAlbumName release];
    
    [super dealloc];
}

#pragma mark NSComparisonMethods

- (BOOL)isEqual:(id)gal
{
    return ([username isEqual:[gal username]] && [[url absoluteString] isEqual:[[gal url] absoluteString]]);
}

- (NSComparisonResult)compare:(id)gal
{
    return [[self identifier] caseInsensitiveCompare:[gal identifier]];
}

#pragma mark Accessors

- (void)setDelegate:(id)newDelegate {
    delegate = newDelegate;
}

- (id)delegate {
    return delegate;
}

- (void)setPassword:(NSString*)newPassword {
    [newPassword retain];
    [password release];
    password = newPassword;
}

- (NSURL*)url {
    return url;
}

- (NSURL*)fullURL {
    return fullURL;
}

- (NSString*)identifier {
    return [NSString stringWithFormat:@"%@%@ (%@)", [url host], [url path], username];
}

- (NSString*)urlString {
    return [url absoluteString];
}

//X-Gallery-Request-Key: 1114d4023d89b15ce10a20ba4333eff7
- (NSString*)requestkey {
    return requestkey;
}

- (NSString*)username {
    return username;
}

- (int)majorVersion {
    return majorVersion;
}

- (int)minorVersion {
    return minorVersion;
}

- (BOOL)loggedIn {
    return loggedIn;
}

- (NSArray*)albums {
    return albums;
}

- (NSMutableArray*)jsonalbums {
    return jsonalbums;
}

- (BOOL)tagsActivated {
    return tagsActivated;
}

- (NSMutableDictionary*)tags {
    return tags;
}


- (NSDictionary*)infoDictionary {
    return [NSDictionary dictionaryWithObjectsAndKeys:
			username, @"username",
			[url absoluteString], @"url",
			[NSNumber numberWithInt:(int)type], @"type",
			nil];
}

- (BOOL)isGalleryV2 {
	return ([self type] == GalleryTypeG2 || [self type] == GalleryTypeG2XMLRPC);
}

- (SCZWGalleryType)type {
    return type;
}

- (NSString *)lastCreatedAlbumName
{
    return lastCreatedAlbumName;
}

- (NSStringEncoding)sniffedEncoding
{
    return sniffedEncoding;
}

#pragma mark Actions

- (void)cancelOperation
{
    if (currentConnection && ![currentConnection isCancelled]) {
        [currentConnection cancel];
    }
}

- (void)login {
    NSDictionary *threadDispatchInfo = [NSDictionary dictionaryWithObjectsAndKeys:
										[NSThread currentThread], @"CallingThread",
										nil];
    [NSThread detachNewThreadSelector:@selector(loginThread:) toTarget:self withObject:threadDispatchInfo];
}

- (void)logout {
    loggedIn = FALSE;
}

- (void)createAlbumWithName:(NSString *)name title:(NSString *)title summary:(NSString *)summary parent:(SCZWGallery *)parent
{
	
	NSString *albumname = nil;
	if (name == nil || [name isEqualToString:@""]) {
		albumname = [NSString stringWithFormat:@"%d", (long)[[NSDate date] timeIntervalSince1970]];
	} else {
		albumname = name;
	}
	
	NSDictionary *threadDispatchInfo;
    if (parent == nil) {
		threadDispatchInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  albumname, @"AlbumName",
							  title, @"AlbumTitle",
							  summary, @"AlbumSummary",
							  [NSNull null], @"AlbumParent",
							  [NSThread currentThread], @"CallingThread",
							  nil];
	} else {
		threadDispatchInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  albumname, @"AlbumName",
							  title, @"AlbumTitle",
							  summary, @"AlbumSummary",
							  parent, @"AlbumParent",
							  [NSThread currentThread], @"CallingThread",
							  nil];
	}
    [NSThread detachNewThreadSelector:@selector(createAlbumThread:) toTarget:self withObject:threadDispatchInfo];
}

- (void)getAlbums {
    NSDictionary *threadDispatchInfo = [NSDictionary dictionaryWithObjectsAndKeys:
										[NSThread currentThread], @"CallingThread",
										nil];
    [NSThread detachNewThreadSelector:@selector(getAlbumsThread:) toTarget:self withObject:threadDispatchInfo];
}

#pragma mark Helpers

/*
 album data = 
 [{"url":"http:\/\/lescoste.net\/gallery3\/rest\/item\/1",
 "entity":{
 "id":"1",
 "captured":null,
 "created":"1282991704",
 "description":"",
 "height":null,
 "level":"1",
 "mime_type":null,
 "name":null,
 "owner_id":"2",
 "rand_key":null,
 "resize_height":null,
 "resize_width":null,
 "slug":"",
 "sort_column":"weight",
 "sort_order":"ASC",
 "thumb_height":"113",
 "thumb_width":"150",
 "title":"Gallery Lescoste.net",
 "type":"album",
 "updated":"1283283475",
 "view_count":"6656",
 "width":null,
 "view_1":"1",
 "view_2":"1",
 "view_3":"1",
 "view_4":"1",
 "view_5":"1",
 "view_6":"1",
 "album_cover":"http:\/\/lescoste.net\/gallery3\/rest\/item\/176",
 "thumb_url":"http:\/\/lescoste.net\/gallery3\/var\/thumbs\/\/.album.jpg?m=1283283475",
 "can_edit":false},
 "relationships":{
 "comments":{"url":"http:\/\/lescoste.net\/gallery3\/rest\/item_comments\/1"},
 "tags":{"url":"http:\/\/lescoste.net\/gallery3\/rest\/item_tags\/1","members":[]}
 },
 "members":["http:\/\/lescoste.net\/gallery3\/rest\/item\/2",
 "http:\/\/lescoste.net\/gallery3\/rest\/item\/5",
 "http:\/\/lescoste.net\/gallery3\/rest\/item\/4",
 "http:\/\/lescoste.net\/gallery3\/rest\/item\/3",
 "http:\/\/lescoste.net\/gallery3\/rest\/item\/6"]}]
 */	
- (NSDictionary *) doGetItem:(NSURL*)itemUrl {
	
	NSMutableDictionary * result = [[NSMutableDictionary alloc] init];
	
	//NSLog ( @"doGetItem: url = %@", itemUrl );
	
	NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL:itemUrl
															  cachePolicy:NSURLRequestReloadIgnoringCacheData
														  timeoutInterval:60.0];
	[theRequest setValue:@"SCiPhotoToGallery3" forHTTPHeaderField:@"User-Agent"];
	
	//NSLog ( @"doGetItem: requestkey = %@", requestkey );
	
	[theRequest setHTTPMethod:@"GET"];
	[theRequest setValue:@"get" forHTTPHeaderField:@"X-Gallery-Request-Method"];
	[theRequest setValue:requestkey forHTTPHeaderField:@"X-Gallery-Request-Key"];
	
	
	currentConnection = [SCZWURLConnection connectionWithRequest:theRequest];
	while ([currentConnection isRunning]) 
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
	
	if ([currentConnection isCancelled]){
		[result setObject: [NSNumber numberWithInt:SCZW_GALLERY_OPERATION_DID_CANCEL] forKey:@"status"];
		NSLog ( @"doGetItem: cancelled, url = %@", itemUrl);
		return result;
	} 
	
	// reponse from server
	
	NSData *data = [currentConnection data];
	
	if (data == nil) {
		[result setObject:[NSNumber numberWithInt:SCZW_GALLERY_COULD_NOT_CONNECT] forKey:@"status"];
		NSLog ( @"doGetItem: error no response, url = %@", itemUrl);
		return result;
	}
	
	id galleryResponse = [self parseResponseData:data];
	if (galleryResponse == nil) {
		[result setObject:[NSNumber numberWithInt:SCZW_GALLERY_PROTOCOL_ERROR] forKey:@"status"];
		NSLog ( @"doGetItem: error wrong response, url = %@, data=%@", itemUrl , data);
		return result;
	}
	
	[result setObject:galleryResponse forKey:@"data"];
	[result setObject:[NSNumber numberWithInt:GR_STAT_SUCCESS] forKey:@"status"];
	return result;	
}	

- (id)parseResponseData:(NSData*)responseData {
	NSString *response = [[[NSString alloc] initWithData:responseData encoding:[self sniffedEncoding]] autorelease];
    
    if (response == nil) {
        NSLog(@"parseResponseData: Could not convert response data into a string with encoding: %i", [self sniffedEncoding]);
        return nil;
    }
    // Create SBJSON object to parse JSON
	SBJsonParser *parser = [SBJsonParser new];
    
	// parse the JSON string into an object - assuming json_string is a NSString of JSON data
	id dict = [parser objectWithString:response error:nil];
	//NSLog ( @"parseResponseData dict = %@", dict );
	
	return dict;
}

- (NSMutableDictionary *) getGalleryTags {
	NSURL* fullReqURL = [[NSURL alloc] initWithString:[[url absoluteString] stringByAppendingString:@"rest/tags"]];
	
	//NSLog ( @"getGalleryTags: url = %@", [fullReqURL absoluteString] );
	
	NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL:fullReqURL
															  cachePolicy:NSURLRequestReloadIgnoringCacheData
														  timeoutInterval:60.0];
	[theRequest setValue:@"SCiPhotoToGallery3" forHTTPHeaderField:@"User-Agent"];
	
	[theRequest setHTTPMethod:@"GET"];
	[theRequest setValue:@"get" forHTTPHeaderField:@"X-Gallery-Request-Method"];
	[theRequest setValue:requestkey forHTTPHeaderField:@"X-Gallery-Request-Key"];
	
	currentConnection = [SCZWURLConnection connectionWithRequest:theRequest];
	while ([currentConnection isRunning]) 
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
	
	if ([currentConnection isCancelled]) 
		return nil;
	
	// reponse from server
	
	NSData *data = [currentConnection data];
	
	if (data == nil) 
		return nil;
	
	NSDictionary *galleryResponse = [self parseResponseData:data];
	
	//NSLog ( @"getGalleryTags: tags  = %@", galleryResponse);
	
	/*
	 tags  = {
	 members =     (
	 "http://lescoste.net/gallery3/index.php/rest/tag/1",
	 "http://lescoste.net/gallery3/index.php/rest/tag/2",
	 "http://lescoste.net/gallery3/index.php/rest/tag/3"
	 );
	 url = "http://lescoste.net/gallery3/index.php/rest/tags";
	 }
	 */
	NSMutableDictionary * tagsDic = [[NSMutableDictionary alloc] init];
	@try {
		if ([galleryResponse isKindOfClass:[NSArray class]]) {
			tagsActivated = FALSE;
			NSLog ( @"getGalleryTags: 'Tags' module may not be activated, galleryResponse=%@" , galleryResponse);
		} else {
			tagsActivated = TRUE;
			NSArray *members = [galleryResponse objectForKey:@"members"];
			int i =0;
			int nbmembers = [members count];
			//	NSLog ( @"getGalleryTags: total tags = %d, galleryResponse=%@", nbmembers , galleryResponse);
			while (i < nbmembers) {
				NSString *tagUrl = [members objectAtIndex:i];
				NSURL* fullReqURL = [[NSURL alloc] initWithString:tagUrl];
				
				NSDictionary * response = [self doGetItem:fullReqURL];
				//		NSLog ( @"getGalleryTags: response  = %@", response );
				SCZWGalleryRemoteStatusCode status = [[response objectForKey:@"status"] intValue];
				
				if (status != GR_STAT_SUCCESS) 
					continue;
				
				NSDictionary * galleryResponse = [response objectForKey:@"data"];
				if (galleryResponse == nil) 
					continue;
				/*
				 galleryResponse tag = {
				 entity =     {
				 count = 2;
				 id = 3;
				 name = fun;
				 };
				 relationships =     {
				 items =         {
				 members =             (
				 "http://lescoste.net/gallery3/index.php/rest/tag_item/3,1550",
				 "http://lescoste.net/gallery3/index.php/rest/tag_item/3,1551"
				 );
				 url = "http://lescoste.net/gallery3/index.php/rest/tag_items/3";
				 };
				 };
				 url = "http://lescoste.net/gallery3/index.php/rest/tag/3";
				 }
				 */
				
				//		NSLog ( @"getGalleryTags: galleryResponse tag = %@", galleryResponse );
				NSString * tagName = [[galleryResponse objectForKey:@"entity"] objectForKey:@"name"];
				//		NSLog ( @"getGalleryTags: galleryResponse add tag = %@", tagName );
				
				
				[tagsDic setObject:tagUrl forKey:tagName];
				
				i++;
			}
			
			NSLog ( @"getGalleryTags: total tags = %d", [tagsDic count] );
		}
	} @catch (NSException *exception) {
		tagsActivated = FALSE;
		NSLog(@"getGalleryTags : Caught %@: %@", [exception name], [exception reason]);
	}
	
	return tagsDic;
}

- (SCZWGalleryRemoteStatusCode)getandparseAlbums:(NSArray*)members {
	
    int i =0;
	int batchSizeMin = 1;
	int batchSizeMax = 200;
	int batchSize = batchSizeMax;
	
	int nbmembers = [members count];
	NSString *requestString = @"type=album&output=json&scope=all&urls=";
	
	NSLog ( @"getandparseAlbums: total albums = %d", nbmembers );
	while (i < nbmembers) {
		
		SCZWGalleryRemoteStatusCode status = SCZW_GALLERY_COULD_NOT_CONNECT;
		NSData *dataFound = nil;
		int startI = i;
		
		while(status != GR_STAT_SUCCESS) {
			
			// go get 100 members data in one request
			// Create SBJSON object to write JSON
			NSMutableArray *urslarray = [[NSMutableArray alloc] init];
			int j =0;
			for (j=0; j < batchSize && i < nbmembers ; j++) {
				NSString *member = [members objectAtIndex:i];
				[urslarray addObject:member];
				i++;
			}
			
			SBJsonWriter *jsonwriter = [SBJsonWriter new];
			NSString *jsonParams = [jsonwriter stringWithObject:urslarray];
			
			NSString *requestbody = [NSString stringWithFormat:@"%@%@",requestString, jsonParams];
			
			NSURL* fullReqURL = [[NSURL alloc] initWithString:[[url absoluteString] stringByAppendingString:@"rest/items"]];
			
			//NSLog ( @"getandparseAlbums: get %d albums starting at %d, url = %@", j, startI, [fullReqURL absoluteString] );
			
			NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL:fullReqURL
																	  cachePolicy:NSURLRequestReloadIgnoringCacheData
																  timeoutInterval:60.0];
			[theRequest setValue:@"SCiPhotoToGallery3" forHTTPHeaderField:@"User-Agent"];
			
			//NSLog ( @"getandparseAlbums: requestkey  = %@", requestkey );
			
			// This request is really a HTTP POST but for the REST API it is a GET !
			[theRequest setValue:@"get" forHTTPHeaderField:@"X-Gallery-Request-Method"];
			[theRequest setValue:requestkey forHTTPHeaderField:@"X-Gallery-Request-Key"];
			[theRequest setHTTPMethod:@"POST"];
			
			NSData *requestData = [requestbody dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
			[theRequest setHTTPBody:requestData];
			
			
			currentConnection = [SCZWURLConnection connectionWithRequest:theRequest];
			while ([currentConnection isRunning]) 
				[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
			
			if ([currentConnection isCancelled]) {
				NSLog ( @"getandparseAlbums: canceled" );
				return SCZW_GALLERY_OPERATION_DID_CANCEL;
			}
			
			// reponse from server
			
			NSData *data = [currentConnection data];
			
			if (data == nil) {
				status = SCZW_GALLERY_COULD_NOT_CONNECT;
				
				if (batchSize <= batchSizeMin) {
					// tried with min size but did'nt work so quit
					break;
				}
				
				// try again with less albums
				// recalculate batchsize
				batchSize = batchSize * 3 / 4;
				if (batchSize < batchSizeMin) batchSize = batchSizeMin;
				// reset starting album
				i = startI;
				NSLog ( @"getandparseAlbums: Error get %d albums starting at %d , retrying", j, startI );
			} else {
				dataFound = data;
				status = GR_STAT_SUCCESS;
				NSLog ( @"getandparseAlbums: Success get %d albums starting at %d ", j, startI );
			}
		}
		
		if (status != GR_STAT_SUCCESS) {
			NSLog ( @"getandparseAlbums: Error response status=%@", status );
			return status;
		}
		
		NSArray *galleryResponse = [self parseResponseData:dataFound];
		if (galleryResponse == nil) {
			NSLog ( @"getandparseAlbums: Error parsing data=%@", dataFound );
			return SCZW_GALLERY_PROTOCOL_ERROR;
		}
		
		//NSLog ( @"getandparseAlbums galleryResponse size : %d", [galleryResponse count] );
		
		// for each album, get sub albums
		for (NSDictionary *dict in galleryResponse) {
			
			NSDictionary *entity = [dict objectForKey:@"entity"];
			NSNumber *canEdit = [entity objectForKey:@"can_edit"];
			
			if ([canEdit intValue] == 1) {
				[jsonalbums addObject:dict];
				
				//	NSString *title = [entity objectForKey:@"title"];
				//NSLog ( @"getandparseAlbums add album : %@ ", title );
				//NSLog ( @"getandparseAlbums jsonalbums size : %d", [jsonalbums count] );
				
			}
		}
	}
	//NSLog ( @"getandparseAlbums end");
	
	
	return GR_STAT_SUCCESS;
}


- (NSString *)formNameWithName:(NSString *)paramName
{
    // Gallery 1 names don't need mangling
    if (![self isGalleryV2]) 
        return paramName;
    
    // For some reason userfile is just changed to g2_userfile
    if ([paramName isEqualToString:@"userfile"])
        return @"g2_userfile";
    
    // All other G2 params are mangled like this:
    return [NSString stringWithFormat:@"g2_form[%@]", paramName];
}

#pragma mark Threads

- (void)loginThread:(NSDictionary *)threadDispatchInfo {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    [NSThread prepareForInterThreadMessages];
	
    NSThread *callingThread = [threadDispatchInfo objectForKey:@"CallingThread"];
    
    SCZWGalleryRemoteStatusCode status = [self doLogin];
    
    if (status == GR_STAT_SUCCESS)
        [delegate performSelector:@selector(galleryDidLogin:) 
                       withObject:self 
                         inThread:callingThread];
    else
        [delegate performSelector:@selector(gallery:loginFailedWithCode:) 
                       withObject:self 
                       withObject:[NSNumber numberWithInt:status] 
                         inThread:callingThread];
    
    [pool release];
}

- (SCZWGalleryRemoteStatusCode)doLogin
{
    // remove the cookies sent to the gallery (the login function ain't so smart)
    NSHTTPCookieStorage *cookieStore = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray *cookies = [cookieStore cookiesForURL:fullURL];
    id cookie;
    NSEnumerator *enumerator = [cookies objectEnumerator];
    while (cookie = [enumerator nextObject]) {
        [cookieStore deleteCookie:cookie];
    }
    
    
    // Default to UTF-8
    sniffedEncoding = NSUTF8StringEncoding;
    
    // Now try to log in 
	// try logging into Gallery v3
	NSLog ( @"doLogin: url = %@", fullURL );
	
	NSMutableURLRequest *theRequest = [NSMutableURLRequest requestWithURL:fullURL
															  cachePolicy:NSURLRequestReloadIgnoringCacheData
														  timeoutInterval:60.0];
	[theRequest setValue:@"iPhotoToGallery3" forHTTPHeaderField:@"User-Agent"];
	// X-Gallery-Request-Method: post
	[theRequest setValue:@"post" forHTTPHeaderField:@"X-Gallery-Request-Method"];
	
	[theRequest setHTTPMethod:@"POST"];
	
	NSString *requestString = [NSString stringWithFormat:@"user=%s&password=%s",
							   [[username stringByEscapingURL] UTF8String], [[password stringByEscapingURL] UTF8String]];
	NSData *requestData = [requestString dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
	[theRequest setHTTPBody:requestData];
	
	currentConnection = [SCZWURLConnection connectionWithRequest:theRequest];
	while ([currentConnection isRunning]) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
	}
	
	if ([currentConnection isCancelled]) 
		return SCZW_GALLERY_OPERATION_DID_CANCEL;
	
	NSData *data = [currentConnection data];
	NSURLResponse *response = [currentConnection response];
	
	if (data == nil) 
		return SCZW_GALLERY_COULD_NOT_CONNECT;
	
    NSString *rzkey = [[[NSString alloc] initWithData:data encoding:[self sniffedEncoding]] autorelease];
	// remove quotes around key
    rzkey = [rzkey substringFromIndex:1];
	int l = [rzkey length] - 1;
    rzkey = [rzkey substringToIndex:l];
    requestkey = [rzkey retain];
	
	
	if ([(NSHTTPURLResponse *)response statusCode] == 200 ) {
		// we successfully logged into a G2
		type = GalleryTypeG2;
        loggedIn = YES;
		
		if (requestkey == nil) {
			NSLog(@"doLogin: Could not read request key with encoding: %i", [self sniffedEncoding]);
			return GR_STAT_PASSWD_WRONG;
		}
		
		if ([requestkey length] > 100) {
			NSLog(@"doLogin: Wrong request key: %@", requestkey);
			return SCZW_GALLERY_COULD_NOT_CONNECT;
		}
		
		NSLog ( @"doLogin: logged in :requestkey = %@",  requestkey );
		
		tags = [self getGalleryTags];
		
		return GR_STAT_SUCCESS;
	}
	if ([(NSHTTPURLResponse *)response statusCode] == 403 ) {
        return GR_STAT_PASSWD_WRONG;
	}    
	NSLog ( @"doLogin: error = %d", [(NSHTTPURLResponse *)response statusCode] );
    
    return SCZW_GALLERY_UNKNOWN_ERROR;
}

- (void)getAlbumsThread:(NSDictionary *)threadDispatchInfo {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
    [NSThread prepareForInterThreadMessages];
	
    NSThread *callingThread = [threadDispatchInfo objectForKey:@"CallingThread"];
    
    SCZWGalleryRemoteStatusCode status = [self doGetAlbums];
    
    if (status == GR_STAT_SUCCESS)
        [delegate performSelector:@selector(galleryDidGetAlbums:) 
                       withObject:self
                         inThread:callingThread];
    else
        [delegate performSelector:@selector(gallery:getAlbumsFailedWithCode:) 
                       withObject:self 
                       withObject:[NSNumber numberWithInt:status] 
                         inThread:callingThread];
	
    [pool release];
}

/*
 20/09/10 21:06:13	iPhoto[84913]	parseResponseData dict = {
 entity =     {
 "album_cover" = "http://lescoste.net/gallery3/index.php/rest/item/176";
 "can_edit" = 0;
 captured = <null>;
 created = 1282991704;
 description = "";
 height = <null>;
 id = 1;
 level = 1;
 "mime_type" = <null>;
 name = <null>;
 "owner_id" = 2;
 "rand_key" = <null>;
 "resize_height" = <null>;
 "resize_width" = <null>;
 slug = "";
 "sort_column" = weight;
 "sort_order" = ASC;
 "thumb_height" = 113;
 "thumb_url" = "http://lescoste.net/gallery3/var/thumbs//.album.jpg?m=1283283475";
 "thumb_width" = 150;
 title = "Gallery Lescoste.net";
 type = album;
 updated = 1283283475;
 "view_1" = 1;
 "view_2" = 1;
 "view_3" = 1;
 "view_4" = 1;
 "view_5" = 1;
 "view_6" = 1;
 "view_count" = 8960;
 width = <null>;
 };
 members =     (
 "http://lescoste.net/gallery3/index.php/rest/item/2",
 "http://lescoste.net/gallery3/index.php/rest/item/5306",
 "http://lescoste.net/gallery3/index.php/rest/item/5308"
 );
 relationships =     {
 comments =         {
 url = "http://lescoste.net/gallery3/index.php/rest/item_comments/1";
 };
 tags =         {
 members =             (
 );
 url = "http://lescoste.net/gallery3/index.php/rest/item_tags/1";
 };
 };
 url = "http://lescoste.net/gallery3/index.php/rest/item/1?type=album&amp;output=json&amp;scope=all";
 }
 */
- (SCZWGalleryRemoteStatusCode)doGetAlbums
{
	
	// store all json albums from gallery
	jsonalbums = [[NSMutableArray alloc] init];                                     
	
	// initial album
	NSString *requestString = @"type=album&output=json&scope=all";
	NSString* escapedUrlString = [requestString stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding];
	NSString *rootAlbumUrl = [[url absoluteString] stringByAppendingString:@"rest/item/1"];
	NSURL* fullReqURL = [[NSURL alloc] initWithString:[[rootAlbumUrl stringByAppendingString:@"?"] stringByAppendingString:escapedUrlString]];
	
	//NSLog ( @"doGetAlbums: url = %@", [fullReqURL absoluteString] );
	
	NSDictionary * response = [self doGetItem:(NSURL *)fullReqURL];
	SCZWGalleryRemoteStatusCode status = [[response objectForKey:@"status"] intValue];
	
	if (status != GR_STAT_SUCCESS) {
		NSLog ( @"doGetAlbums: error status= %@", status );
		return status;
	}
	
	NSDictionary * galleryResponse = [response objectForKey:@"data"];
	if (galleryResponse == nil) {
		NSLog ( @"doGetAlbums: error parsing response= %@", response );
		return SCZW_GALLERY_PROTOCOL_ERROR;
	}
	
	
	NSArray *members = [galleryResponse objectForKey:@"members"];
	//NSLog ( @"parseResponseData members = %@", members );
	
    status = [self getandparseAlbums:members];
	
	NSLog ( @"doGetAlbums: editable albums = %d", [jsonalbums count] );
	
    [albums release];
    albums = nil;
    
	if (status != GR_STAT_SUCCESS) {
		NSLog ( @"doGetAlbums: error status getandparseAlbums = %@", status );
		return status;
	}
    
    // add the albums to myself here...
    int numAlbums = [jsonalbums count];
    NSMutableArray *galleriesArray = [NSMutableArray array];
	NSDictionary *entity = [galleryResponse objectForKey:@"entity"];
	
    SCZWGalleryAlbum *albumRoot = nil;
	NSNumber *canEdit = [entity objectForKey:@"can_edit"];
	
	if ([canEdit intValue] == 1) {
		albumRoot = [SCZWGalleryAlbum albumWithTitle:[entity objectForKey:@"title"] name:[entity objectForKey:@"name"] gallery:self];
		[albumRoot setUrl:rootAlbumUrl];
		BOOL a_can_add = YES;
		[albumRoot setCanAddItem:a_can_add];
		BOOL a_can_create_sub = YES;
		[albumRoot setCanAddSubAlbum:a_can_create_sub];
    } else {
		albumRoot = [SCZWGalleryAlbum albumWithTitle:@"" name:@"" gallery:self];
	}
		
	[galleriesArray addObject:albumRoot];
    int i;
	Boolean addBasicAuth = ([url user] != nil);
		
    NSMutableDictionary *galleriesPerUrl = [[NSMutableDictionary alloc] init];
    // first we'll iterate through to create the objects, since we don't know if they'll be in an order
    // where parents will always come before children
    for (i = 0; i < numAlbums; i++) {
		
		NSDictionary *galleryAlbum =  [jsonalbums objectAtIndex:i];
		NSDictionary *entity = [galleryAlbum objectForKey:@"entity"];
		NSString *albumurl = [galleryAlbum objectForKey:@"url"];

		NSString *albumUrlWithAuth = albumurl;
		if (addBasicAuth) {
			// add basic http authent if needed
			NSString *galleryURLWithAuth = [url absoluteString];
			NSRange restRange = [albumurl rangeOfString:@"rest"];
			//	NSLog ( @"doGetAlbums test : %d %@ restRange = loc %d  lenght %d", i, albumurl, restRange.location, restRange.length );
			int debRest = restRange.location;
			if (debRest > 0) {
				NSRange range = NSMakeRange(0, debRest);
				albumUrlWithAuth = [albumurl stringByReplacingCharactersInRange:range withString:galleryURLWithAuth];
				//		NSLog ( @"doGetAlbums added : %d %@ httpauth = %@", i, albumurl, albumUrlWithAuth );
			}
		}
		
        NSString *a_name = [entity objectForKey:@"name"];
        NSString *a_title = [entity objectForKey:@"title"];
		NSString *parent = [entity objectForKey:@"parent"];

		NSString *parentUrlWithAuth = parent;
		if (addBasicAuth) {
			// add basic http authent if needed
			NSString *galleryURLWithAuth = [url absoluteString];
			NSRange restRange = [parent rangeOfString:@"rest"];
			//	NSLog ( @"doGetAlbums test : %d %@ restRange = loc %d  lenght %d", i, albumurl, restRange.location, restRange.length );
			int debRest = restRange.location;
			if (debRest > 0) {
				NSRange range = NSMakeRange(0, debRest);
				parentUrlWithAuth = [parent stringByReplacingCharactersInRange:range withString:galleryURLWithAuth];
				//		NSLog ( @"doGetAlbums added : %d %@ httpauth = %@", i, albumurl, albumUrlWithAuth );
			}
		}
		
		[galleriesPerUrl setValue:[NSNumber numberWithInt:i+1] forKey:albumUrlWithAuth];
		
		SCZWGalleryAlbum *album = [SCZWGalleryAlbum albumWithTitle:a_title name:a_name gallery:self];
		[album setUrl:albumUrlWithAuth];
		[album setParenturl:parentUrlWithAuth];
		
        // this album will use the delegate of the gallery we're on
        [album setDelegate:[self delegate]];
        
        BOOL a_can_add = YES;
        [album setCanAddItem:a_can_add];
        BOOL a_can_create_sub = YES;
        [album setCanAddSubAlbum:a_can_create_sub];
        [galleriesArray addObject:album];
		
		//NSLog ( @"doGetAlbums added : %d %@", i, a_title );
    }
	
	
	/* find the parent
	 */
	for (i = 1; i <= numAlbums; i++) {
		SCZWGalleryAlbum *album = [galleriesArray objectAtIndex:i];
		
		NSString *parenturl = [album parenturl];
		//NSLog ( @"doGetAlbums parent : %d %@", i, parenturl );
		
        if (parenturl != nil) {
			NSNumber *album_parent_id = [galleriesPerUrl objectForKey:parenturl];
			int pid = [album_parent_id intValue];
			if ([parenturl isLike:@"*rest/item/1"]) {
				pid = 0;
			}
			//NSLog ( @"doGetAlbums parentid : %d %d", i, pid );
			
			
			SCZWGalleryAlbum *parent = [galleriesArray objectAtIndex:pid];
			
			[album setParent:parent];
			[parent addChild:album];
        } else {
			NSLog ( @"doGetAlbums: no parentid found : %d %@", i, [album name] );
		}
    }
    albums = [[NSArray alloc] initWithArray:galleriesArray];
    
    return GR_STAT_SUCCESS;
}

- (void)createAlbumThread:(NSDictionary *)threadDispatchInfo {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    [NSThread prepareForInterThreadMessages];
    
    NSThread *callingThread = [threadDispatchInfo objectForKey:@"CallingThread"];
    
    SCZWGalleryRemoteStatusCode status = [self doCreateAlbumWithName:[threadDispatchInfo objectForKey:@"AlbumName"]
															   title:[threadDispatchInfo objectForKey:@"AlbumTitle"]
															 summary:[threadDispatchInfo objectForKey:@"AlbumSummary"]
															  parent:[threadDispatchInfo objectForKey:@"AlbumParent"]];
    
    if (status == GR_STAT_SUCCESS)
        [delegate performSelector:@selector(galleryDidCreateAlbum:) 
                       withObject:self
                         inThread:callingThread];
    else
        [delegate performSelector:@selector(gallery:createAlbumFailedWithCode:) 
                       withObject:self 
                       withObject:[NSNumber numberWithInt:status] 
                         inThread:callingThread];
    
    [pool release];
}


/*
 POST /gallery3/index.php/rest/item/1 HTTP/1.1
 Host: example.com
 X-Gallery-Request-Method: post
 X-Gallery-Request-Key: ...
 Content-Type: application/x-www-form-urlencoded
 Content-Length: 117
 entity=%7B%22type%22%3A%22album%22%2C%22name%22%3A%22Sample+Album%22%2C%22title%22%3A%22  
 This+is+my+Sample+Album%22%7D
 
 entity {
 type: "album"
 name: "Sample Album"
 title: "This is my Sample Album"
 }
 
 */
- (SCZWGalleryRemoteStatusCode)doCreateAlbumWithName:(NSString *)name title:(NSString *)title summary:(NSString *)summary parent:(SCZWGalleryAlbum *)parent
{    
    NSString *parentUrl;
    if (parent != nil && ![parent isKindOfClass:[NSNull class]]) {
        parentUrl = [parent url];
	} else {
		NSURL *aURL = [[NSURL alloc] initWithString:[[url absoluteString] stringByAppendingString:@"rest/item/1"]];
        parentUrl = [aURL absoluteString]; 
    }
	
	//NSLog ( @"doCreateAlbumWithName: title : %@ , parent url : %@", title, parentUrl );
	
	// Create SBJSON object to write JSON
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
	[dict setObject:name forKey:@"name"];
	[dict setObject:title forKey:@"title"];
	[dict setObject:summary forKey:@"description"];
	[dict setObject:@"album" forKey:@"type"];
	
	NSArray *galleryResponse = [self doCreateObjectWithData:dict url:parentUrl ];
	
	if (galleryResponse == nil) {
		NSLog ( @"doCreateAlbumWithName: error no response title : %@ , parent url : %@", title, parentUrl );
	    return SCZW_GALLERY_PROTOCOL_ERROR;
	}
	
	[lastCreatedAlbumName release];
	lastCreatedAlbumName = [name copy];
	NSLog ( @"doCreateAlbumWithName: title : %@ , parent url : %@ album added : %@", title, parentUrl, galleryResponse );
	
    return GR_STAT_SUCCESS;
}


/*
 POST /gallery3/index.php/rest/tags HTTP/1.1
 Host: example.com
 X-Gallery-Request-Method: post
 X-Gallery-Request-Key: ...
 Content-Type: application/x-www-form-urlencoded
 Content-Length: 117
 entity=%7B%22type%22%3A%22album%22%2C%22name%22%3A%22Sample+Album%22%2C%22title%22%3A%22  
 This+is+my+Sample+Album%22%7D
 
 entity {
 name: "Sample tag"
 }
 
 */
- (SCZWGalleryRemoteStatusCode)doCreateTagWithName:(NSString *)name
{    
	if (!tagsActivated) return GR_STAT_SUCCESS;
	
	NSURL *aURL = [[NSURL alloc] initWithString:[[url absoluteString] stringByAppendingString:@"rest/tags"]];
	
	//NSLog ( @"doCreateTagWithName: name : %@", name );
	
	// Create SBJSON object to write JSON
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
	[dict setObject:name forKey:@"name"];
	
	id galleryResponse = [self doCreateObjectWithData:dict url:[aURL absoluteString] ];
	
	if (galleryResponse == nil) {
		NSLog ( @"doCreateTagWithName: error no response name : %@", name );
	    return SCZW_GALLERY_PROTOCOL_ERROR;
	}
	
	// add tag in local memory
	[tags setObject:[galleryResponse objectForKey:@"url"] forKey:name];
	
	/*
	 28/09/10 09:07:31	iPhoto[24137]	doCreateTagWithName: tag added : {
	 url = "http://lescoste.net/gallery3/index.php/rest/tag/4";
	 }
	 */
	NSLog ( @"doCreateTagWithName: tag added :name=%@ %@", name, galleryResponse );
	
    return GR_STAT_SUCCESS;
}

- (SCZWGalleryRemoteStatusCode)doLinkTag:(NSString *)tagUrl withPhoto:(NSString *)photoUrl
{    
	if (!tagsActivated) return GR_STAT_SUCCESS;

	NSURL *aURL = [[NSURL alloc] initWithString:[[url absoluteString] stringByAppendingString:@"rest/tag_items"]];
	
	//NSLog ( @"doLinkTag: tagUrl: %@ photoUrl: %@", tagUrl, photoUrl );
	if (tagUrl == nil || photoUrl == nil) {
		NSLog ( @"doLinkTag: error :something is nil tagUrl: %@ photoUrl: %@", tagUrl, photoUrl );
		return GR_STAT_SUCCESS;
	}
	
	// Create SBJSON object to write JSON
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
	[dict setObject:tagUrl forKey:@"tag"];
	[dict setObject:photoUrl forKey:@"item"];
	
	NSMutableDictionary * galleryResponse = [self doCreateObjectWithData:dict url:[aURL absoluteString] ];
	
	if (galleryResponse == nil) {
		NSLog ( @"doLinkTag: error no response tagUrl: %@ photoUrl: %@", tagUrl, photoUrl );
	    return SCZW_GALLERY_PROTOCOL_ERROR;
	}
	
	NSLog ( @"doLinkTag: tag linked : %@", [galleryResponse objectForKey:@"url"] );
	
	/*
	 28/09/10 10:16:59	iPhoto[25079]	doLinkTag: tag linked : {
		members =     {
			item = "http://lescoste.net/gallery3/index.php/rest/item/5341";
			tag = "http://lescoste.net/gallery3/index.php/rest/tag/4";
		};
		url = "http://lescoste.net/gallery3/index.php/rest/tag_item/4,5341";
	 }
	 */
    return GR_STAT_SUCCESS;
}


- (id)doCreateObjectWithData:(NSMutableDictionary *)dict  url:(NSString *)aurl
{    
	
	NSURL* purl = [[NSURL alloc] initWithString:aurl];
	
	SBJsonWriter *jsonwriter = [SBJsonWriter new];
	NSString *jsonParams = [jsonwriter stringWithObject:dict];
	
	//NSString* escapedJsonData = [jsonData stringByAddingPercentEscapesUsingEncoding:[self sniffedEncoding]];
	NSString* escapedJsonData = [[NSString alloc] initWithFormat:@"entity=%@", jsonParams];
	//NSLog ( @"doCreateObjectWithData: escapedJsonData : %@ ", escapedJsonData );
	
	NSData* requestData = [escapedJsonData dataUsingEncoding:[self sniffedEncoding]];
	//NSLog ( @"doCreateAlbumWithName: requestData : %@ ", requestData );
	NSString* requestDataLengthString = [[NSString alloc] initWithFormat:@"%d", [requestData length]];
	//NSLog ( @"doCreateAlbumWithName: requestDataLengthString : %@ ", requestDataLengthString );
	
	//NSLog ( @"doCreateObjectWithData: url : %@ ", purl );
	
	NSMutableURLRequest* request = [[NSMutableURLRequest alloc] initWithURL:purl];
	[request setHTTPMethod:@"POST"];
	[request setHTTPBody:requestData];
	[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[request setValue:requestDataLengthString forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"iPhotoToGallery3" forHTTPHeaderField:@"User-Agent"];
	[request setValue:@"post" forHTTPHeaderField:@"X-Gallery-Request-Method"];
	[request setValue:requestkey forHTTPHeaderField:@"X-Gallery-Request-Key"];
	[request setTimeoutInterval:60.0];
	
    currentConnection = [SCZWURLConnection connectionWithRequest:request];
    while ([currentConnection isRunning]) 
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    
    if ([currentConnection isCancelled]) 
        return nil;
    
    NSData *data = [currentConnection data];
	
	NSURLResponse *response = [currentConnection response];
	
    if (data == nil) 
        return nil;
    
    id galleryResponse = [self parseResponseData:data];
	if (galleryResponse == nil) 
        return nil;
	
	if ([(NSHTTPURLResponse *)response statusCode] != 201 ) {
		NSLog ( @"doCreateObjectWithData: status code : %d", [(NSHTTPURLResponse *)response statusCode] );
        return nil;
	}
	//NSLog ( @"doCreateObjectWithData:  added : %@", galleryResponse );
	
    return galleryResponse;
}

@end
