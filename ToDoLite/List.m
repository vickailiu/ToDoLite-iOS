//
//  List.m
//  ToDo Lite
//
//  Created by Jens Alfke on 8/22/13.
//
//

#import "List.h"
#import "Task.h"
#import "Profile.h"

#define kListDocType @"list"

@implementation List

@dynamic owner, members;

+ (NSString*) docType {
    return kListDocType;
}

// Returns a query for all the lists in a database.
+ (CBLQuery*) queryListsInDatabase: (CBLDatabase*)db {
    CBLView* view = [db viewNamed: @"lists"];
    if (!view.mapBlock) {
        // Register the map function, the first time we access the view:
        [view setMapBlock: MAPBLOCK({
            if ([doc[@"type"] isEqualToString:kListDocType])
                emit(doc[@"title"], nil);
        }) reduceBlock: nil version: @"1"]; // bump version any time you change the MAPBLOCK body!
    }
    return [view createQuery];
}

+ (void) updateAllListsInDatabase: (CBLDatabase*)database withOwner: (Profile*)owner error: (NSError**)error {
    CBLQueryEnumerator *myLists = [[List queryListsInDatabase:database] run:error];
    if (!myLists) {
        return;
    }
    
    for (CBLQueryRow* row in myLists) {
        List* list = [List modelForDocument: row.document];
        list.owner = owner;
        if (![list save:error]) {
            return;
        }
    }
}

// Creates a new task.
- (Task*) addTaskWithTitle: (NSString*)title withImage: (NSData*)image withImageContentType: (NSString*)contentType {
    Task *task = [Task modelForNewDocumentInDatabase:self.database];
    task.title = title;
    task.list_id = self;
    [task setImage:image contentType:contentType];
    return task;
}

// Returns a query for this list's tasks, in reverse chronological order.
- (CBLQuery*) queryTasks {
    CBLView* view = [self.document.database viewNamed: @"tasksByDate"];
    if (!view.mapBlock) {
        // On first query after launch, register the map function:
        NSString* const kTaskDocType = [Task docType];
        [view setMapBlock: MAPBLOCK({
            if ([doc[@"type"] isEqualToString: kTaskDocType]) {
                id date = doc[@"created_at"];
                NSString* listID = doc[@"list_id"];
                emit(@[listID, date], doc);
            }
        }) reduceBlock: nil version: @"4"]; // bump version any time you change the MAPBLOCK body!
    }
    
    // Configure the query. Since it's in descending order, the startKey is the maximum key,
    // while the endKey is the _minimum_ key. (The empty object @{} is a placeholder that's
    // greater than any actual value.) Got that?
    CBLQuery* query = [view createQuery];
    query.descending = YES;
    NSString* myListId = self.document.documentID;
    query.startKey = @[myListId, @{}];
    query.endKey = @[myListId];
    return query;
}

// Delete list
- (BOOL)deleteList: (NSError**)error {
    CBLQueryEnumerator* tasks = [[self queryTasks] run: error];
    for (CBLQueryRow* row in tasks) {
        if (![row.document.currentRevision deleteDocument: error]) {
            return NO;
        }
    }
    return [self deleteDocument: error];
}

@end
