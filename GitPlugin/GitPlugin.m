#import "GitPlugin.h"
#define NDEBUG

@import AppKit;
@import JavaScriptCore;
@interface TextFieldDelegate : NSTextField
@property NSButton *okButton;
@end

@implementation TextFieldDelegate
- (void)textDidChange:(NSNotification *)notification {
    NSTextView *textField = [notification object];
    [_okButton setEnabled:![[textField string] isEqualToString:@""]];
    [super textDidChange:notification];
}

@end

@implementation GitPlugin
+ (void) showAlert: (NSString*) message {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"Ok"];
    [alert setMessageText:@"Git Plugin"];
    [alert setInformativeText:message];
    [alert runModal];
}

+ (NSString*) getUserInput: (NSString*) message {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:message];
    [alert addButtonWithTitle:@"Ok"];
    [alert addButtonWithTitle:@"Cancel"];
    
    NSArray *buttons = [alert buttons];
    NSButton *okButton = (NSButton*)([buttons objectAtIndex:0]);
    [okButton setEnabled:false];
    
    TextFieldDelegate *input = [[TextFieldDelegate alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    [input setOkButton:okButton];
    [input setStringValue:@""];
    [alert setAccessoryView:input];
    
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        return [input stringValue];
    }
    return nil;
}

+ (void) exec: (NSArray*) args client: (NSURL *)url_client action_name: (NSString *)action_name document: (NSObject *) document {
    NSArray *firstArgs = [NSArray arrayWithObjects: @"-m", @"dystopia.client/com.dystopia.server.GitClient", nil];
    NSArray *allArgs = [firstArgs arrayByAddingObjectsFromArray:args];
    
    NSTask *task = [[NSTask alloc] init];
    [task setExecutableURL:url_client];
    [task setArguments:allArgs];
    
#ifndef NDEBUG
    NSPipe* outPipe = [NSPipe pipe];
    NSPipe* errPipe = [NSPipe pipe];
    [task setStandardOutput:outPipe];
    [task setStandardError:errPipe];
#endif
    
    
    [task setTerminationHandler: ^(NSTask *task){
#ifndef NDEBUG
        NSData* errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
        NSData* data = [[outPipe fileHandleForReading] readDataToEndOfFile];
        NSString *message = @"";
        if (errData != nil && [errData length]) {
            message = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
        } else if (data != nil && [data length]) {
            message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        if ([message length]) {
            dispatch_async(dispatch_get_main_queue(), ^(void){
                [GitPlugin showAlert:message];
            });
        }
#endif
        dispatch_async(dispatch_get_main_queue(), ^(void){
            if ([task terminationStatus] != 0) {
                [GitPlugin showAlert:[NSString stringWithFormat:@"An error occurred while executing %@ action", action_name]];
            }
            else {
                SEL selectorFileURL = NSSelectorFromString(@"showMessage:");
                NSURL* (*fileURL)(id, SEL, id) = (void *)[document methodForSelector:selectorFileURL];
                fileURL(document, selectorFileURL, [NSString stringWithFormat:@"%@ executed successfully", action_name]);
            }
        });
    }];
    [task launchAndReturnError:nil];
}

+ (void) runCommand: (NSObject*) document plugin: (NSObject*) plugin command: (NSString *) command {
    @try {
        SEL selectorFileURL = NSSelectorFromString(@"fileURL");
        NSURL* (*fileURL)(id, SEL) = (void *)[document methodForSelector:selectorFileURL];
        NSURL* url = fileURL(document, selectorFileURL);
        
        if (![[url scheme] isEqualToString:@"file"]) {
            [GitPlugin showAlert:@"Only local files can be under version control."];
            return;
        }
        
        NSString* filePath = [url path];
        SEL selectorUrlForResourceNamed = NSSelectorFromString(@"urlForResourceNamed:");
        NSURL* (*urlForResourceNamed)(id, SEL, id) = (void *)[plugin methodForSelector:selectorUrlForResourceNamed];
        NSURL* urlClient = urlForResourceNamed(plugin, selectorUrlForResourceNamed, @"dist/bin/java");
        
        if ([command isEqualToString:@"start_id"]) {
            [GitPlugin exec: [NSArray arrayWithObjects:@"start", filePath, nil] client:urlClient action_name:@"Start" document:document];
        }
        else if ([command isEqualToString:@"stop_id"]) {
            [GitPlugin exec: [NSArray arrayWithObjects:@"stop", filePath, nil] client:urlClient action_name:@"Stop" document:document];
        }
        else if ([command isEqualToString:@"synchronize_id"]) {
            [GitPlugin exec: [NSArray arrayWithObjects:@"pull", filePath, nil] client:urlClient action_name:@"Synchronize" document:document];
        } else if ([command isEqualToString:@"publish_id"]) {
            NSString* commitMessage = [GitPlugin getUserInput:@"Enter commit message:"];
            if (commitMessage == nil) {
                return;
            }
            [GitPlugin exec: [NSArray arrayWithObjects:@"push", filePath, commitMessage, nil] client:urlClient action_name:@"Publish" document:document];
        }
    }
    @catch (NSException *e) {
        NSLog(@"%@", [e reason]);
        [GitPlugin showAlert:[e reason]];
    }
}
@end
