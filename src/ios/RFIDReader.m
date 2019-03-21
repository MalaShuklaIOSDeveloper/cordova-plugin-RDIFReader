/********* RFIDReader.m Cordova Plugin Implementation *******/

#import <TSLAsciiCommands/TSLAsciiCommander.h>
#import <TSLAsciiCommands/TSLInventoryCommand.h>
#import <TSLAsciiCommands/TSLLoggerResponder.h>
#import <TSLAsciiCommands/TSLFactoryDefaultsCommand.h>
#import <TSLAsciiCommands/TSLVersionInformationCommand.h>
#import <TSLAsciiCommands/TSLBinaryEncoding.h>
#import <TSLAsciiCommands/TSLWriteSingleTransponderCommand.h>
#import <TSLAsciiCommands/TSLReadTransponderCommand.h>
#import <Cordova/CDV.h>


@interface RFIDReader : CDVPlugin {
    TSLAsciiCommander* _commander;
    TSLInventoryCommand* _inventoryResponder;
    TSLReadTransponderCommand* _readCommand;
    EAAccessory* _rfidGun;
    BOOL _inWriteMode;
    CDVInvokedUrlCommand* _command;
    CDVPluginResult* _pluginResult;
    
    NSArray * _accessoryList; //------> List of available devices connected to phone via bluetooth
    NSArray * _rfidScanners; //----> List of devices
    NSInteger _chosenDeviceIndex; //---->Device index
    NSInteger _transpondersSeen; //-----> Number of tags read in scan
    NSString* _resultMessage; //----> String to hold tag data to be returned to main app
    NSMutableDictionary *_transpondersRead;
}

- (void)pair:(CDVInvokedUrlCommand*)cordovaComm;
- (void)read:(CDVInvokedUrlCommand*)cordovaComm;
- (void)write:(CDVInvokedUrlCommand*)cordovaComm;
- (void)reconnect:(CDVInvokedUrlCommand*)cordovaComm;
- (void)disconnect:(CDVInvokedUrlCommand*)cordovaComm;
- (NSInteger)getGunIndex;
@end

@implementation RFIDReader


/* Pairing method
 - Pair the app to a bluetooth connected RFID device and send commands to the device
 - Commands allows the guns trigger to be pulled to identify all nearby Tags */


-(void)pair:(CDVInvokedUrlCommand*)cordovaComm{
    //[self.commandDelegate runInBackground:^{
    _pluginResult = nil;
    _resultMessage = @"";
    _transpondersSeen = 0;
    _rfidScanners = @[@"1128"];
    _inWriteMode = false;
    
    /* Store the command to send back tag data to the main app.*/
    
    _command = cordovaComm;
    
    /* Create the TSLAsciiCommander used to communicate with the TSL Reader */
    
    _commander = [[TSLAsciiCommander alloc] init];
    _accessoryList = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    _transpondersRead = [[NSMutableDictionary alloc] init];
    
    do{
        /* Disconnect from the current reader, if any */
        [_commander disconnect];
        
        _accessoryList = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
        NSLog(@"Accessory list has %ld items", _accessoryList.count);
        
        /* Find the first RFID scanner in the array */
        _chosenDeviceIndex = [self getGunIndex];
        
        if(_chosenDeviceIndex != -1){
            // Connect to the chosen TSL Reader
            _rfidGun = _accessoryList[_chosenDeviceIndex];
            [_commander connect:_rfidGun];
        }
        else{
            _resultMessage = @"Scanner not found.";
            NSLog(@"Scanner not found.");
            _pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:_resultMessage];
            [_pluginResult setKeepCallbackAsBool:YES];
            [self.commandDelegate sendPluginResult:_pluginResult callbackId:cordovaComm.callbackId];
            _resultMessage = @"";
            [NSThread sleepForTimeInterval:2.0f];
        }
    } while(!_commander.isConnected);
    
    // Issue commands to the reader
    NSLog(@"Commander is connected!");
    
    // Add a logger to the commander to output all reader responses to the log file
    [_commander addResponder:[[TSLLoggerResponder alloc] init]];
    
    // Some synchronous commands will be used in the app
    [_commander addSynchronousResponder];
    
    // The TSLInventoryCommand is a TSLAsciiResponder for inventory responses and can have a delegate
    // (id<TSLInventoryCommandTransponderReceivedDelegate>) that is informed of each transponder as it is received
    
    // Create a TSLInventoryCommand
    _inventoryResponder = [[TSLInventoryCommand alloc] init];
    
    // Add self as the transponder delegate
    _inventoryResponder.transponderReceivedDelegate = (id) self;
    
    // Pulling the Reader trigger will generate inventory responses that are not from the library.
    // To ensure these are also seen requires explicitly requesting handling of non-library command responses
    _inventoryResponder.captureNonLibraryResponses = YES;
    
    // Add the inventory responder to the commander's responder chain
    [_commander addResponder:_inventoryResponder];
    
    // Ensure the reader is in a known (default) state
    // No information is returned by the reset command other than its succesful completion
    TSLFactoryDefaultsCommand * resetCommand = [TSLFactoryDefaultsCommand synchronousCommand];
    
    [_commander executeCommand:resetCommand];
    
    // Notify user device has been reset
    if( resetCommand.isSuccessful ){
        NSLog(@"Reader reset to Factory Defaults\n");
    }
    else{
        NSLog(@"!!! Unable to reset reader to Factory Defaults !!!\n");
    }
    
    // Get version information for the reader
    // Use the TSLVersionInformationCommand synchronously as the returned information is needed below
    TSLVersionInformationCommand * versionCommand = [TSLVersionInformationCommand synchronousCommand];
    
    [_commander executeCommand:versionCommand];
    
    // Log some of the values obtained
    NSLog( @"\n%-16s %@\n%-16s %@\n%-16s %@\n\n\n",
          "Manufacturer:", versionCommand.manufacturer,
          "Serial Number:", versionCommand.serialNumber,
          "Antenna SN:", versionCommand.antennaSerialNumber
          );
    
    _resultMessage = [NSString stringWithFormat:@"%@ is connected.", versionCommand.serialNumber];
    _pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:_resultMessage];
    [_pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:_pluginResult callbackId:cordovaComm.callbackId];
    _resultMessage = @"";
}




/* Once tags have been identified by the command, EPC numbers can be passed to the read function to pull more detailed off the tags */

- (void)read:(CDVInvokedUrlCommand*)cordovaComm{
    
    NSString* epc = [cordovaComm.arguments objectAtIndex:0];
    NSString* readResult = @"";
    // Display the target transponder
    NSLog(@"Read from: %@", epc);
    
    @try
    {
        _readCommand = [[TSLReadTransponderCommand alloc] init];
        _readCommand = [TSLReadTransponderCommand synchronousCommand];
        _readCommand.selectBank = TSL_DataBank_ElectronicProductCode; //--->Use the select parameters to write to a single tag
        _readCommand.selectData = epc; //---->Set the match pattern to the full EPC
        _readCommand.selectOffset = 32; //----> This offset is in bits
        _readCommand.selectLength = (int)epc.length * 4;//----> This length is in bits
        _readCommand.offset = 0;//---->Set the locations to read from
        _readCommand.length = 8;
        _readCommand.accessPassword = 0; //--->This demo only works with open tags
        _readCommand.bank = TSL_DataBank_User; //--->Set the bank to be used
        
        /* Set self as delgate to listen for each transponder read - there may be more than one that can match */
        
        _readCommand.transponderReceivedDelegate = (id)self;
        
        /* Collect the responses in a dictionary */
        
        _transpondersRead = [NSMutableDictionary dictionary];
        [_commander executeCommand:_readCommand];
        
        
        // Display the data returned
        if( _transpondersRead.count == 0 ){
            readResult = @"Transponder not found.";
        }
        else{
            // There should only be one response in the dictionary
            for( NSData *tagData in [_transpondersRead objectEnumerator] ){
                if( tagData.length != 0 ){
                    readResult = [readResult stringByAppendingString:[TSLBinaryEncoding toBase16String:tagData]];
                }
                else{
                    readResult = @"None defined.";
                }
            }
        }
        
    }
    @catch (NSException *exception){
        NSLog(@"Exception: %@\n\n", exception.reason);
    }
    
    NSLog(@"Final read result: %@", readResult);
    _pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:readResult];
    [_pluginResult setKeepCallbackAsBool:NO];
    [self.commandDelegate sendPluginResult:_pluginResult callbackId:cordovaComm.callbackId];
}

/*Tags that have been identified by the inventory command with an EPC number can now be written to
 with this function.
 It overwrites the user data field. */

-(void)write:(CDVInvokedUrlCommand*)cordovaComm {
    @try{
        NSString* epc = [cordovaComm.arguments objectAtIndex:0];
        NSString* writeData = [cordovaComm.arguments objectAtIndex:1];
        
        TSLWriteSingleTransponderCommand* command = [TSLWriteSingleTransponderCommand synchronousCommand];//---->Creates a command for writing to a tag, but it must be configured
        
        NSLog(@"epc to find: %@", epc);
        NSLog(@"data to write: %@", writeData);
        command.selectBank = TSL_DataBank_ElectronicProductCode;//--->Use the select parameters to write to a single tag
        command.selectData = epc;
        command.selectOffset = 32; //----> This offset is in bits
        command.selectLength = (int)epc.length * 4;//---->This length is in bits
        
        //Default password for open tag
        command.accessPassword = 0;
        //Set bank to EPC
        command.bank = TSL_DataBank_User;
        //Set the data to be written
        command.data = [TSLBinaryEncoding fromBase16String:writeData];
        // Set the locations to write to - this demo writes all the data supplied
        command.offset = 0;
        command.length = (int)command.data.length / 2; // This length is in words
        [_commander executeCommand:command];
        NSLog(@"Write to: %@\n", epc);
        
        if( command.isSuccessful ){
            NSLog(@"Data written successfully");
        }
        else{
            NSLog(@"Data write FAILED\n");
            for (NSString *msg in command.messages){
                NSLog(@"Command message: %@", msg);
            }
        }
    }
    @catch (NSException *exception){
        NSLog(@"Exception: %@\n\n", exception.reason);
    }
    
    _resultMessage = @"Write callback";
    _pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:_resultMessage];
    [_pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:_pluginResult callbackId:cordovaComm.callbackId];
    _resultMessage = @"";
    // }];
}

-(NSInteger)getGunIndex {
    for (int i = 0; i < _accessoryList.count; i++) {
        if([_rfidScanners containsObject:((EAAccessory*) _accessoryList[i]).name])
            return i;
    }
    return -1;
}

//Receiver method for the inventory command (specified in the pair function)
//Each transponder received from the reader is passed to this method
//Parameters epc, crc, pc, and rssi may be nil
//
//Note: This is an asynchronous call from a separate thread
//
-(void)transponderReceived:(NSString *)epc crc:(NSNumber *)crc pc:(NSNumber *)pc rssi:(NSNumber *)rssi fastId:(NSData *)fastId moreAvailable:(BOOL)moreAvailable {
    _resultMessage = [_resultMessage stringByAppendingFormat:@"%-24s", [epc UTF8String]];
    if (moreAvailable) {
        _resultMessage = [_resultMessage stringByAppendingFormat:@"--"];
    }
    _transpondersSeen++;
    
    // If this is the last transponder send the results back to the app
    if( !moreAvailable ){
        NSLog(@"Result Message: %@", _resultMessage);
        if (_resultMessage != nil && [_resultMessage length] > 0) {
            _pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:_resultMessage];
        } else {
            _pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
        }
        
        [_pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:_pluginResult callbackId:_command.callbackId];
        
        _transpondersSeen = 0;
        _resultMessage = @"";
    }
}

/* Receiver method for the read command, specified in the read function */

-(void)transponderReceivedFromRead:(NSString *)epc crc:(NSNumber *)crc pc:(NSNumber *)pc rssi:(NSNumber *)rssi index:(NSNumber *)index data:(NSData *)readData moreAvailable:(BOOL)moreAvailable{
    if( epc != nil ){
        if( readData != nil ){
            [_transpondersRead setObject:readData forKey:epc];
        }
        else{
            NSLog(@"No data for transponder: %@", epc);
        }
    }
}


/* The following methods control commander when app enters and exits background.  Not yet sure if these are helpful for a Cordova project. */

- (void)disconnect:(CDVInvokedUrlCommand *)cordovaComm{
    [_commander disconnect];
    NSLog(@"Application became inactive");
}

- (void)reconnect:(CDVInvokedUrlCommand *)cordovaComm{
    // Attempt to reconnect to the last used accessory
    [_commander connect:nil];
    NSLog(@"Application became active");
}

@end
