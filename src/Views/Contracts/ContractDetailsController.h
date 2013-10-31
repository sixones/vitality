/*
 This file is part of Mac Eve Tools.
 
 Mac Eve Tools is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 Mac Eve Tools is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with Mac Eve Tools.  If not, see <http://www.gnu.org/licenses/>.
 
 Copyright Matt Tyson, 2009.
 */

#import <Cocoa/Cocoa.h>

@class Character;
@class Contract;
@class MTISKFormatter;

@interface ContractDetailsController : NSWindowController <NSURLDownloadDelegate>
{
    IBOutlet NSTextField *typeField;
    IBOutlet NSTextField *statusField;
    IBOutlet NSTextField *contractIDField;
    IBOutlet NSTextField *startStationField;
    IBOutlet NSTextField *endStationField;
    IBOutlet NSTextField *volumeField;
    IBOutlet NSTextField *priceField;
    IBOutlet NSTextField *rewardField;
    IBOutlet NSTextField *collateralField;
    IBOutlet NSTextField *buyoutField;
    
    IBOutlet NSTableView *itemTable;
    
	Contract *contract;
	Character *character;
	MTISKFormatter *iskFormatter;
}


/*Display a ship, given the typeID of the ship*/
+(void) displayContract:(Contract *)_contract forCharacter:(Character*)ch;

@end
