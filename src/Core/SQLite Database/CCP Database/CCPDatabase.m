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

#import "CCPDatabase.h"
#import "CCPGroup.h"
#import "CCPCategory.h"
#import "CCPType.h"
#import "CCPTypeAttribute.h"

#import "CCPAttributeData.h"

#import "METShip.h"
#import "METDependSkill.h"

#import "Helpers.h"
#import "macros.h"

#import "SkillPair.h"

#import "Config.h"

#import "SkillAttribute.h"

#import "CertTree.h"
#import "CertPair.h"
#import "Cert.h"
#import "CertClass.h"
#import "CertCategory.h"



#import <sqlite3.h>

@interface CCPDatabase()
-(BOOL)insertAttributeTypes:(NSString *)queryString number:(int)attrNum;
-(void)buildAttributeTypes;
-(BOOL)updateCertRelationships;
@end

@implementation CCPDatabase

@synthesize lang;

-(CCPDatabase*) initWithPath:(NSString*)dbpath
{
	if(self = [super initWithPath:dbpath]){
		[self openDatabase];
		tran_stmt = NULL;
		lang = [[Config sharedInstance]dbLanguage];
        if( db )
        {
            [self buildAttributeTypes];
            [self buildTypePrerequisites];
            [self updateCertRelationships];
        }
	}
	return self;
}

-(void) dealloc
{
	[self closeDatabase];
	[super dealloc];
}

-(void) closeDatabase
{
	if(tran_stmt != NULL){
		sqlite3_finalize(tran_stmt);
		tran_stmt = NULL;
	}
	
	[super closeDatabase];
}

-(NSInteger) dbVersion
{
	const char query[] =
		"SELECT versionNum FROM version;";
	
	sqlite3_stmt *read_stmt;
	NSInteger version = -1;
	
	int rc;
	
	rc = sqlite3_prepare_v2(db,query, (int)sizeof(query), &read_stmt, NULL);
	
	if(rc != SQLITE_OK){
		return -1;
	}
	
	if(sqlite3_step(read_stmt) == SQLITE_ROW){
		version = sqlite3_column_nsint(read_stmt,0);
	}
	
	sqlite3_finalize(read_stmt);
	
	return version;
}

-(NSString*) dbName
{
	const char query[] = 
		"SELECT versionName FROM version;";
	sqlite3_stmt *read_stmt;
	int rc;
	NSString *result = @"N/A";
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
		return result;
	}
	
	if(sqlite3_step(read_stmt) == SQLITE_ROW){
		result = sqlite3_column_nsstr(read_stmt,0);
	}
	
	sqlite3_finalize(read_stmt);
	
	return result;
}

-(CCPCategory*) category:(NSInteger)categoryID
{
	const char query[] = 
		"SELECT categoryID, categoryName FROM invCategories WHERE categoryID = ? "
		"ORDER BY categoryName;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,categoryID);
	
	CCPCategory *cat = nil;
	
	if(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger cID = sqlite3_column_nsint(read_stmt,0);
		const unsigned char *str = sqlite3_column_text(read_stmt,1);
		NSString *cName = [NSString stringWithUTF8String:(const char*)str];
	
		cat = [[CCPCategory alloc]initWithCategory:cID
											  name:cName
										  database:self];
		[cat autorelease];
	}
	
	sqlite3_finalize(read_stmt);
	
	return cat;
}

-(NSInteger) categoryCount
{
	const char query[] = "SELECT COUNT(*) FROM invCategories;";
	return [self performCount:query];
}

-(NSArray*) categoriesInDB
{
	return nil;
}

#pragma mark groups

-(NSInteger) groupCount:(NSInteger)categoryID
{
	NSLog(@"Insert code here");
	return 0;
}


-(CCPGroup*) group:(NSInteger)groupID
{
	const char query[] = "SELECT groupID, categoryID, groupName FROM invGroups WHERE groupID = ?;";
	sqlite3_stmt *read_stmt;
	CCPGroup *group = nil;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,groupID);
	
	if(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger groupID,categoryID;
		NSString *groupName;
		
		groupID = sqlite3_column_nsint(read_stmt,0);
		categoryID = sqlite3_column_nsint(read_stmt,1);
		groupName = sqlite3_column_nsstr(read_stmt,2);
		
		group = [[CCPGroup alloc] initWithGroup:groupID
									   category:categoryID 
									  groupName:groupName
									   database:self];
		[group autorelease];
	}
	
	sqlite3_finalize(read_stmt);
	
	return group;
}

-(NSString*) translation:(NSInteger)keyID 
			   forColumn:(NSInteger)columnID
				fallback:(NSString*)fallback
{
	const char query[] = 
		"SELECT text "
		"FROM trnTranslations "
		"WHERE tcID = ? AND keyID = ? AND languageID = ?;";
	NSString *result = nil;
	
	if(tran_stmt == NULL){
		sqlite3_prepare_v2(db,query,(int)sizeof(query),&tran_stmt,NULL);
	}
	
	sqlite3_bind_nsint(tran_stmt,1,columnID);
	sqlite3_bind_nsint(tran_stmt,2,keyID);
	sqlite3_bind_text(tran_stmt,3, langCodeForId(lang),2, NULL);
	
	int rc = sqlite3_step(tran_stmt);
	if((rc == SQLITE_DONE) || (rc == SQLITE_ROW)){
		result = sqlite3_column_nsstr(tran_stmt,0); //returns an empty string on failure.
	}else{
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
	}
	
	sqlite3_reset(tran_stmt);
	sqlite3_clear_bindings(tran_stmt);
	
	return [result length] > 0 ? result : fallback;
}

-(NSArray*) groupsInCategory:(NSInteger)categoryID
{
	const char query[] = 
		"SELECT groupID, categoryID, groupName " 
		"FROM invGroups WHERE categoryID = ? "
		"ORDER BY groupName;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,categoryID);
	
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger groupID,categoryID;
		NSString *groupName = nil;
		CCPGroup *group;
		
		groupID = sqlite3_column_nsint(read_stmt,0);
		categoryID = sqlite3_column_nsint(read_stmt,1);
		groupName = sqlite3_column_nsstr(read_stmt,2);
		
		if(lang != l_EN){
			groupName = [self translation:groupID forColumn:TRN_GROUP_NAME fallback:groupName];
		}
				
		group = [[CCPGroup alloc]initWithGroup:groupID
									  category:categoryID 
									 groupName:groupName
									  database:self];
		[array addObject:group];
		[group release];		
	}
	
	sqlite3_finalize(read_stmt);
	
	return array;
}

#pragma mark typeSMInt

-(NSInteger) typeCount:(NSInteger)groupID
{
	//const char query[] = "SELECT COUNT(*) FROM invTypes WHERE typeID = ?;";
	NSLog(@"Insert code here");
	return 0;
}

-(CCPType*) type:(NSInteger)typeID
{
 	const char query[] =
    "SELECT typeID, groupID, raceID, marketGroupID, mass, "
    "volume, capacity,basePrice, typeName, description "
    "FROM invTypes "
    "WHERE typeID = ? ";
 	sqlite3_stmt *read_stmt;
 	int rc;

 	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
 	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
        return nil;
    }
    
 	sqlite3_bind_nsint(read_stmt,1,typeID);
    
    NSMutableArray *array = [NSMutableArray array];
    
    [self parseTypesResults:array sqliteReadStmt:read_stmt];
    
 	sqlite3_finalize(read_stmt);
    
    if( [array count] > 0 )
        return [[[array objectAtIndex:0] retain] autorelease];
    
    return nil;
}

/* Instead of adding the entire invTypes table to the Vitality download,
  I created a new table with typeID, typeName and description, and loaded all published types.
 */
-(NSString *) typeName:(NSInteger)typeID
{
 	const char query[] =
    "SELECT typeName "
    "FROM metTypeNames "
    "WHERE typeID = ? ";
 	sqlite3_stmt *read_stmt;
 	int rc;
    
 	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
 	if(rc != SQLITE_OK)
    {
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
        return nil;
    }
    
 	sqlite3_bind_nsint(read_stmt,1,typeID);
    
    NSString *typeName = NULL;
    
	while( !typeName && (sqlite3_step(read_stmt) == SQLITE_ROW) )
    {
		typeName = sqlite3_column_nsstr(read_stmt,0);
		
		if(lang != l_EN)
        {
			typeName = [self translation:typeID forColumn:TRN_TYPE_NAME fallback:typeName];
		}
    }
    
 	sqlite3_finalize(read_stmt);
    
    return typeName;
}

-(void) parseTypesResults:(NSMutableArray*)array sqliteReadStmt:(sqlite3_stmt*)read_stmt
{
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		
		NSInteger typeID = sqlite3_column_nsint(read_stmt,0);
		NSString *description = sqlite3_column_nsstr(read_stmt,9);
		NSString *typeName = sqlite3_column_nsstr(read_stmt,8);
		
		if(lang != l_EN){
			description = [self translation:typeID forColumn:TRN_TYPE_DESCRIPTION fallback:description];
			typeName = [self translation:typeID forColumn:TRN_TYPE_NAME fallback:typeName];
		}
		
		CCPType *type = [[CCPType alloc]
						 initWithType:sqlite3_column_nsint(read_stmt,0)
						 group:sqlite3_column_nsint(read_stmt,1)
						 race:sqlite3_column_nsint(read_stmt,2)
						 marketGroup:sqlite3_column_nsint(read_stmt,3)
						 mass:sqlite3_column_double(read_stmt,4)
						 volume:sqlite3_column_double(read_stmt,5)
						 capacity:sqlite3_column_double(read_stmt,6)
						 basePrice:sqlite3_column_double(read_stmt,7)
						 typeName:typeName
						 typeDesc:description
						 database:self];
        
        // graphic:sqlite3_column_nsint(read_stmt,2)
        // radius:sqlite3_column_double(read_stmt,5)
		
		[array addObject:type];
		[type release];		
	}
}

-(NSArray*) typesInGroup:(NSInteger)groupID
{
	const char query[] = 
		"SELECT typeID, groupID, raceID, marketGroupID, mass, "
		"volume, capacity,basePrice, typeName, description "
		"FROM invTypes "
		"WHERE groupID = ? "
		"ORDER BY typeName;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,groupID);
	
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	
	[self parseTypesResults:array sqliteReadStmt:read_stmt];
	
	sqlite3_finalize(read_stmt);
	
	return array;
}

-(NSArray*) prereqForType:(NSInteger)typeID
{
	const char query[] = 
		"SELECT skillTypeID, skillLevel FROM typePrerequisites WHERE typeID = ? ORDER BY skillOrder;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger skillTypeID = sqlite3_column_nsint(read_stmt,0);
		NSInteger skillLevel = sqlite3_column_nsint(read_stmt,1);
		SkillPair *pair = [[SkillPair alloc]initWithSkill:
						   [NSNumber numberWithInteger:skillTypeID] 
												level:skillLevel];
		[array addObject:pair];
		[pair release];
	}
	
	sqlite3_finalize(read_stmt);
	
	return array;
}

-(BOOL) parentForTypeID:(NSInteger)typeID parentTypeID:(NSInteger*)parent metaGroupID:(NSInteger*)metaGroup
{
	const char query[] = 
		"SELECT parentTypeID, metaGroupID FROM invMetaTypes WHERE typeID = ?;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return NO;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		if(parent != NULL){
			*parent = sqlite3_column_nsint(read_stmt,0);
		}
		if(metaGroup != NULL){
			*metaGroup = sqlite3_column_nsint(read_stmt,1);
		}
	}
	
	sqlite3_finalize(read_stmt);
	
	return YES;
}

-(NSInteger) metaLevelForTypeID:(NSInteger)typeID
{
	NSInteger metaLevel = -1;
	const char query[] =
		"SELECT COALESCE(valueInt,valueFloat) FROM dgmTypeAttributes WHERE attributeID = 633 AND typeID = ?;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return -1;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		metaLevel = sqlite3_column_nsint(read_stmt,0);
	}
	
	sqlite3_finalize(read_stmt);
	
	return metaLevel;
}

-(BOOL) isPirateShip:(NSInteger)typeID
{
	BOOL result = NO;
	
	const char query[] = 
		"SELECT COALESCE(valueInt,valueFloat) FROM dgmTypeAttributes WHERE attributeID = 793 AND typeID = ?;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query), &read_stmt, NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return -1;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		result = YES;
	}
	
	sqlite3_finalize(read_stmt);
	
	return result;
}

-(NSDictionary*) typeAttributesForTypeID:(NSInteger)typeID
{
	const char query[] =
		"SELECT at.attributeID, at.displayName, un.displayName, ta.valueInt, ta.valueFloat "
		"FROM dgmTypeAttributes ta, dgmAttributeTypes at, eveUnits un "
		"WHERE at.attributeID = ta.attributeID "
		"AND un.unitID = at.unitID "
		"AND ta.typeID = ?;";

	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db, query, (int)sizeof(query), &read_stmt, NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	NSMutableDictionary *attributes = [[[NSMutableDictionary alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger attributeID = sqlite3_column_nsint(read_stmt,0);
		NSString *dispName = sqlite3_column_nsstr(read_stmt, 1);
		NSString *unitDisp = sqlite3_column_nsstr(read_stmt, 2);
		
		NSInteger vInt;
		
		if(sqlite3_column_type(read_stmt,3) == SQLITE_NULL){
			vInt = NSIntegerMax;
		}else{
			vInt = sqlite3_column_nsint(read_stmt,3);
		}
		
		CGFloat vFloat;
		
		if(sqlite3_column_type(read_stmt, 4) == SQLITE_NULL){
			vFloat = CGFLOAT_MAX;
		}else{
			vFloat = (CGFloat) sqlite3_column_double(read_stmt, 4);
		}
		
		NSNumber *attrNum = [NSNumber numberWithInteger:attributeID];
		
		CCPTypeAttribute *ta = [CCPTypeAttribute createTypeAttribute:attributeID
															dispName:dispName 
														 unitDisplay:unitDisp
															valueInt:vInt 
														  valueFloat:vFloat];
		
		[attributes setObject:ta forKey:attrNum];
	}
	
	sqlite3_finalize(read_stmt);
	
	return attributes;
}

/*
-(METShip*) shipForTypeID:(NSInteger)typeID
{
	CCPType *shipType = [self type:typeID];
	NSDictionary *typeAttr = [self typeAttributesForTypeID:typeID];
}
*/

-(NSArray*) attributeForType:(NSInteger)typeID groupBy:(enum AttributeTypeGroups)group
{
	const char query[] =
	"SELECT COALESCE(at.displayName,at.attributeName), ta.valueInt, "
		"ta.valueFloat, at.attributeID, un.displayName "
	"FROM dgmTypeAttributes ta, metAttributeTypes at LEFT OUTER JOIN eveUnits un ON at.unitID = un.unitID "
	"WHERE at.attributeID = ta.attributeID "
	"AND typeID = ? "
	"AND at.displayType = ?;";
	
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db, query, (int)sizeof(query), &read_stmt, NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	sqlite3_bind_nsint(read_stmt,2,group);
	
	NSMutableArray *attributes = [[[NSMutableArray alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSString *displayName = sqlite3_column_nsstr(read_stmt,0);
		NSInteger attrID = sqlite3_column_nsint(read_stmt,3);
		NSString *unitDisplay = sqlite3_column_nsstr(read_stmt,4);
		
		NSInteger vInt;
		
		if(sqlite3_column_type(read_stmt,1) == SQLITE_NULL){
			vInt = NSIntegerMax;
		}else{
			vInt = sqlite3_column_nsint(read_stmt,1);
		}
		
		CGFloat vFloat;
		
		if(sqlite3_column_type(read_stmt, 2) == SQLITE_NULL){
			vFloat = CGFLOAT_MAX;
		}else{
			vFloat = (CGFloat) sqlite3_column_double(read_stmt, 2);
		}
		
		CCPTypeAttribute *ta = [CCPTypeAttribute createTypeAttribute:attrID
															dispName:displayName 
														 unitDisplay:unitDisplay
															valueInt:vInt 
														  valueFloat:vFloat];
		
		[attributes addObject:ta];
	}
	
	sqlite3_finalize(read_stmt);
	
	if([attributes count] == 0){
		return nil;
	}
	
	return attributes;
}

//select ta.*,at.attributeName from dgmTypeAttributes ta INNER JOIN dgmAttributeTypes at ON ta.attributeID = at.attributeID where typeID = 17636;

#pragma mark Certs

/*return an array of skill prerequisites*/
-(NSArray*) privateCertSkillPrereqs:(NSInteger)certID
{
	const char query[] =
		"SELECT parentTypeID, parentLevel "
		"FROM crtRelationships "
		"WHERE childID = ? "
		"AND parentTypeID IS NOT NULL AND parentTypeID IS NOT 0;";
	sqlite3_stmt *read_stmt;
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	int rc;
	
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
		NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,certID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger skillID;
		NSInteger skillLevel;
		
		skillID = sqlite3_column_nsint(read_stmt,0);
		skillLevel = sqlite3_column_nsint(read_stmt,1);
		
		SkillPair *pair = [[SkillPair alloc]initWithSkill:[NSNumber numberWithInteger:skillID]
													level:skillLevel];
		
		[array addObject:pair];
		
		[pair release];
	}
	
	sqlite3_finalize(read_stmt);
	
	if([array count] == 0){
		return nil;
	}
	
	return array;
}

/*return an array of certificate prerequistes*/
-(NSArray*) privateCertCertPrereqs:(NSInteger)certID
{
	const char query[] =
	/*
		"SELECT parentID "
		"FROM crtRelationships "
		"WHERE childID = ? "
		"AND parentTypeID IS NULL;";
	*/
		"SELECT parentID, "
			"(SELECT grade FROM crtCertificates "
			"WHERE certificateID = parentID) AS grade "
		"FROM crtRelationships "
		"WHERE childID = ? AND grade IS NOT NULL;";
	
	sqlite3_stmt *read_stmt;
	
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,certID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger pCertID;
		NSInteger certGrade;
		
		pCertID = sqlite3_column_nsint(read_stmt,0);
		certGrade = sqlite3_column_nsint(read_stmt,1);
		
		CertPair *cp = [CertPair createCertPair:pCertID certGrade:certGrade];
		
		[array addObject:cp];
	}
	
	sqlite3_finalize(read_stmt);
	
	if([array count] == 0){
		return nil;
	}
	
	return array;
}

/*return an array of certs beloning to the classID*/
-(NSArray*) privateParseCert:(NSInteger)certClassID 
				   certClass:(CertClass*)parent
					certDict:(NSMutableDictionary*)allCerts
{
	const char query[] = 
		"SELECT certificateID,grade,description "
		"FROM crtCertificates "
		"WHERE classID = ? "
		"ORDER BY grade;";
	
	sqlite3_stmt *read_stmt;
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,certClassID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger certID;
		NSInteger certGrade;
		NSString  *certDesc;
		NSArray *skillArray;
		NSArray *certArray;
		
		certID = sqlite3_column_nsint(read_stmt,0);
		certGrade = sqlite3_column_nsint(read_stmt,1);

		certDesc = sqlite3_column_nsstr(read_stmt,2);
		
		if(lang != l_EN){
			certDesc = [self translation:certID 
							   forColumn:TRN_CRTCRT_DESCRIPTION 
								fallback:certDesc];
		}
		
		skillArray = [self privateCertSkillPrereqs:certID];
		certArray = [self privateCertCertPrereqs:certID];
		
		Cert *c = [Cert createCert:certID
							 grade:certGrade
							  text:certDesc 
						  skillPre:skillArray 
						   certPre:certArray 
						 certClass:parent];
		
		[array addObject:c];
		
		[allCerts setObject:c forKey:[NSNumber numberWithInteger:certID]];
	}
	
	sqlite3_finalize(read_stmt);
	
	return array;	
}

/*return an array of CertClass objects for a given category*/
-(NSArray*) privateParseCertClass:(NSInteger)catID 
						 certDict:(NSMutableDictionary*)allCerts
{
	const char query[] = 
		"SELECT cla.classID,cla.className "
		"FROM crtClasses cla, crtCertificates crt, crtCategories cat "
		"WHERE cla.classID = crt.classID "
		"AND cat.categoryID = crt.categoryID "
		"AND cat.categoryID = ? "
		"GROUP BY cla.classID;";
	
	
	sqlite3_stmt *read_stmt;
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	int rc;
	
	rc = sqlite3_prepare_v2(db, query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,catID);
	
	while( (rc = sqlite3_step(read_stmt)) == SQLITE_ROW){
		NSString *className;
		NSInteger classID;
		
		classID = sqlite3_column_nsint(read_stmt,0);
		className = sqlite3_column_nsstr(read_stmt,1);
		
		if(lang != l_EN){
			className = [self translation:classID
								forColumn:TRN_CRTCLS_NAME 
								 fallback:className];
		}
		
		CertClass *cc = [CertClass createCertClass:classID
											  desc:className];
		
		NSArray *certArray = [self privateParseCert:classID certClass:cc certDict:allCerts];
		
		[cc setCertArray:certArray];
		
		[array addObject:cc];
	}
	
	sqlite3_finalize(read_stmt);
	
	return array;
}

/*
	return an array of certificate categories.
	this will be filled out completly;
 */
-(NSArray*) privateParseCertCategories:(NSMutableDictionary*)dict;
{
	const char query[] = 
		"SELECT categoryID,categoryName "
		"FROM crtCategories";
	sqlite3_stmt *read_stmt;
	NSMutableArray *array = [[[NSMutableArray alloc]init]autorelease];
	int rc;
	
	rc = sqlite3_prepare_v2(db, query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger catID;
		NSString *catName;
		
		catID = sqlite3_column_nsint(read_stmt,0);
		catName = sqlite3_column_nsstr(read_stmt,1);
		
		if(lang != l_EN){
			catName = [self translation:catID
							  forColumn:TRN_CRTCAT_NAME
							   fallback:catName];
		}
		
		NSArray *certClassArray = [self privateParseCertClass:catID certDict:dict];
		
		CertCategory *ccat = [CertCategory createCertCategory:catID
														 name:catName 
													   cClass:certClassArray];
		
		[array addObject:ccat];
	}
	
	sqlite3_finalize(read_stmt);
	
	return array;
}

-(CertTree*) buildCertTree
{
	NSMutableDictionary *dict = [[[NSMutableDictionary alloc]init]autorelease];
	NSArray *catArray = [self privateParseCertCategories:dict];
	
	return [CertTree createCertTree:catArray certDict:dict];
}

// Not sure how, but my copy of the database had zeroes in the parentTypeID column instead of NULLS
// So update them all.
- (BOOL)updateCertRelationships
{
    return YES;
    NSInteger cnt = [self performCount:"SELECT COUNT(*) FROM crtRelationships WHERE parentTypeID = 0;"];
    if( 0 == cnt )
        return YES;
    
    const char update[] = "UPDATE crtRelationships SET parentTypeID = NULL WHERE parentTypeID = 0;";
	sqlite3_stmt *update_stmt;
	int rc = sqlite3_prepare_v2( db, update,(int)sizeof(update),&update_stmt,NULL);
    if( rc != SQLITE_OK )
    {
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
        sqlite3_finalize(update_stmt);
		return NO;
	}
    
    rc = sqlite3_step(update_stmt);
    if( rc != SQLITE_OK )
    {
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
        sqlite3_finalize(update_stmt);
		return NO;
	}
    
    sqlite3_finalize(update_stmt);
    
    return YES;
}

#pragma mark Skills



/*returns an array of skills beloning to a particular group*/
-(BOOL) privateParseSkillGroup:(NSInteger)groupID 
						 group:(SkillGroup*)skillGroup
						  tree:(SkillTree*)skillTree
{
	const char skill_query[] = 
		"SELECT typeID, typeName, description "
		"FROM invTypes "
		"WHERE groupID = ? "
		"ORDER BY typeName;";
	
	//Find the primary and secondary skill attributes.
	const char skill_attr_query[] = 
		"SELECT attributeID, COALESCE(valueInt,valueFloat) AS value "
		"FROM dgmTypeAttributes "
		"WHERE typeID = ? "
		"AND attributeID IN (180,181,275) "
		"ORDER BY attributeID;";
	
	//Fetch all the attributes.
	const char attr_query[] =
		"SELECT ta.attributeID, at.attributeName, ta.valueInt, ta.valueFloat "
		"FROM dgmAttributeTypes at INNER JOIN dgmTypeAttributes ta "
		"ON at.attributeID = ta.attributeID "
		"WHERE ta.typeID = ?;";
	
	
	sqlite3_stmt *skill_stmt;
	sqlite3_stmt *skillattr_stmt;
	sqlite3_stmt *attr_stmt;
	
	//NSMutableArray *array;
	int rc;
	
	rc = sqlite3_prepare_v2(db,skill_query,(int)sizeof(skill_query),&skill_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return NO;
	}
	
	rc = sqlite3_prepare_v2(db,skill_attr_query,(int)sizeof(skill_attr_query),&skillattr_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		sqlite3_finalize(skillattr_stmt);
		return NO;
	}
	
	rc = sqlite3_prepare_v2(db, attr_query, (int)sizeof(attr_query), &attr_stmt, NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		sqlite3_finalize(skillattr_stmt);
		sqlite3_finalize(skill_stmt);
		return NO;
	}
	
	sqlite3_bind_nsint(skill_stmt,1,groupID);
	
	while(sqlite3_step(skill_stmt) == SQLITE_ROW){
		NSInteger typeID;
		NSString *typeName;
		NSString *desc;
		
		NSInteger primary;
		NSInteger secondary;
		NSInteger rank;
		
		typeID = sqlite3_column_nsint(skill_stmt,0);
		typeName = sqlite3_column_nsstr(skill_stmt,1);
		desc = sqlite3_column_nsstr(skill_stmt,2);
		
		if(lang != l_EN){
			typeName = [self translation:typeID 
							   forColumn:TRN_TYPE_NAME 
								fallback:typeName];
			
			desc = [self translation:typeID
						   forColumn:TRN_TYPE_DESCRIPTION 
							fallback:desc];
		}
		
		/*Get the basic stuff like primary and secondary attributes*/
		
		sqlite3_bind_nsint(skillattr_stmt,1,typeID);
		
		sqlite3_step(skillattr_stmt);
		primary = sqlite3_column_nsint(skillattr_stmt,1);
		sqlite3_step(skillattr_stmt);
		secondary = sqlite3_column_nsint(skillattr_stmt,1);
		sqlite3_step(skillattr_stmt);
		rank = sqlite3_column_nsint(skillattr_stmt,1);
		
		sqlite3_reset(skillattr_stmt);
		sqlite3_clear_bindings(skillattr_stmt);

		
		/*
		 
		 Get all the skill attributes for this skill.
		 */
		
	
		
		Skill *s = [[Skill alloc]initWithDetails:typeName 
										   group:[NSNumber numberWithInteger:groupID]
											type:[NSNumber numberWithInteger:typeID]];
		[s setSkillRank:rank];
		[s setPrimaryAttr:attrCodeForDBInt(primary)];
		[s setSecondaryAttr:attrCodeForDBInt(secondary)];
		[s setSkillDescription:desc];
		
		NSArray *pre = [self prereqForType:typeID];
		[s addPrerequisteArray:pre];
		
		[skillTree addSkill:s toGroup:[NSNumber numberWithInteger:groupID]];
		
		//load all the attributes for this skill
		sqlite3_bind_nsint(attr_stmt,1,typeID);
		
		while(sqlite3_step(attr_stmt) == SQLITE_ROW){
			NSInteger attributeID = sqlite3_column_nsint(attr_stmt,0);
			
			NSInteger valueInt = NSIntegerMax;
			CGFloat valueFloat = CGFLOAT_MAX;
			BOOL isInt;
			if(sqlite3_column_type(attr_stmt,2) == SQLITE_NULL){
				//type is an int
				valueInt = sqlite3_column_nsint(attr_stmt,2);
				isInt = YES;
			}else{
				valueFloat = (CGFloat) sqlite3_column_double(attr_stmt, 3);
				isInt = NO;
			}
			
			SkillAttribute *attr = [[SkillAttribute alloc]initWithAttributeID:attributeID
																	 intValue:valueInt 
																   floatValue:valueFloat
																	  valType:isInt];
			
			[s addAttribute:attr];
			[attr release];
			
		}
		sqlite3_reset(attr_stmt);
		sqlite3_clear_bindings(attr_stmt);
		//done loading all attributes for this skill
		
		[s release];
	}
	
	sqlite3_finalize(skillattr_stmt);
	sqlite3_finalize(skill_stmt);
	sqlite3_finalize(attr_stmt);
	
	return YES;
}

-(SkillTree*) buildSkillTree
{
	const char query[] =
		"SELECT groupID, groupName "
		"FROM invGroups "
		"WHERE categoryID = 16 " 
		"ORDER BY groupName;";
	
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	SkillTree *st = [[[SkillTree alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger groupID;
		NSString *groupName;
		
		groupID = sqlite3_column_nsint(read_stmt,0);
		groupName = sqlite3_column_nsstr(read_stmt,1);
		
		SkillGroup *sg = [[SkillGroup alloc]initWithDetails:groupName
													  group:[NSNumber numberWithInteger:groupID]];
		[st addSkillGroup:sg];
		
		[sg release];
		
		[self privateParseSkillGroup:groupID group:sg tree:st];
		
	}
	
	sqlite3_finalize(read_stmt);
	
	return st;
}

-(NSMutableDictionary*) dependenciesForSkillByCategory:(NSInteger)typeID
{
	const char query[] = 
		"SELECT invTypes.typeID, typeName, skillLevel, invCategories.categoryID, categoryName "
		"FROM invTypes JOIN typePrerequisites ON (invTypes.typeID = typePrerequisites.typeID) "
		"JOIN invGroups ON (invGroups.groupID = invTypes.groupID) "
		"JOIN invCategories ON (invCategories.categoryID = invGroups.categoryID) "
		"WHERE skillTypeID = ? "
		"ORDER BY invCategories.categoryID, typeName;";
	
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db, query, (int)sizeof(query), &read_stmt, NULL);
	if(rc != SQLITE_OK){
		NSLog(@"%s: Query error - %s",__func__,sqlite3_errmsg(db));
		return nil;
	}
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	NSInteger currentCategoryID = -1;
	NSMutableArray *array = nil;
	NSString *oldCatName = nil;
	NSMutableDictionary *dict = [[[NSMutableDictionary alloc]init]autorelease];
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		NSInteger itemTypeID = sqlite3_column_nsint(read_stmt,0);
		NSString *itemName = sqlite3_column_nsstr(read_stmt,1);
		NSInteger itemSkillLevel = sqlite3_column_nsint(read_stmt,2);
		NSInteger itemCategory = sqlite3_column_nsint(read_stmt,3);
			
		
		METDependSkill *item = [[METDependSkill alloc]initWithData:itemTypeID 
														  itemName:itemName 
													   skillPreTID:typeID 
													   skillPLevel:itemSkillLevel
													  itemCategory:itemCategory];
		
		if(currentCategoryID != itemCategory){
			if(array != nil){
				//store the old array.
				[dict setValue:array forKey:oldCatName];
				[array release];
				array = nil;
			}
			currentCategoryID = itemCategory;
			array = [[NSMutableArray alloc]init];
			oldCatName = sqlite3_column_nsstr(read_stmt, 4);
		}
		
		[array addObject:item];
		[item release];
	}
	
	if(array != nil){
		[dict setValue:array forKey:oldCatName];
		[array release];
	}
	
	return dict;
}

-(NSDictionary*) attributesForType:(NSInteger)typeID
{
	const char query[] =
		"SELECT attributeID, attributeName, COALESCE(valueFloat,valueInt) "
		"FROM dgmTypeAttributes "
		"JOIN dgmAttributeTypes USING(attributeID) "
		"WHERE typeID = ?;";
	
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	NSMutableDictionary *attrDict = [[[NSMutableDictionary alloc]init]autorelease];
	
	sqlite3_bind_nsint(read_stmt,1,typeID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW){
		
		NSInteger attrID = sqlite3_column_nsint(read_stmt,0);
		NSString *attrName = sqlite3_column_nsstr(read_stmt,1);
		CGFloat value = sqlite3_column_cgfloat(read_stmt,2);
		
		CCPAttributeData *attr = [[CCPAttributeData alloc]initWithValues:attrID value:value name:attrName];
		
		[attrDict setObject:attr forKey:[NSNumber numberWithInteger:attrID]];
		
		[attr release];
	}
	
	sqlite3_finalize(read_stmt);
	
	return attrDict;
}

#pragma mark AttributeTypes

-(BOOL)insertAttributeTypes:(NSString *)queryString number:(int)attrNum
{
	sqlite3_stmt *read_stmt;
	int rc;
    
	rc = sqlite3_prepare_v2( db, [queryString UTF8String], (int)[queryString length], &read_stmt, NULL );
	if( rc != SQLITE_OK )
    {
		[self logError:"Error preparing Attribute type query"];
		return NO;
	}
    
    const char insert_attr[] = "INSERT INTO metAttributeTypes VALUES (?,?,?,?,?,?)";
    sqlite3_stmt *insert_attr_stmt;
    
    rc = sqlite3_prepare_v2( db, insert_attr, (int)sizeof(insert_attr), &insert_attr_stmt, NULL);
    
	sqlite3_bind_nsint( insert_attr_stmt, 6, attrNum );
    
	while( sqlite3_step(read_stmt) == SQLITE_ROW )
    {
		NSInteger attrID = sqlite3_column_nsint(read_stmt,0);
		NSInteger unitID = sqlite3_column_nsint(read_stmt,1);
		NSInteger iconID = sqlite3_column_nsint(read_stmt,2);
		NSString *displayName = sqlite3_column_nsstr(read_stmt,3);
		NSString *attrName = sqlite3_column_nsstr(read_stmt,4);
        
        rc = sqlite3_bind_nsint( insert_attr_stmt, 1, attrID );
        rc = sqlite3_bind_nsint( insert_attr_stmt, 2, unitID );
        rc = sqlite3_bind_nsint( insert_attr_stmt, 3, iconID );
        rc = sqlite3_bind_text( insert_attr_stmt, 4, [displayName UTF8String], (int)[displayName length], NULL );
        rc = sqlite3_bind_text( insert_attr_stmt, 5, [attrName UTF8String], (int)[attrName length], NULL );
        
        if( (rc = sqlite3_step(insert_attr_stmt)) != SQLITE_DONE )
        {
            NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
            return NO;
        }
        sqlite3_reset(insert_attr_stmt);
	}
    
    sqlite3_finalize(insert_attr_stmt);
	sqlite3_finalize(read_stmt);
    
	return YES;
    
}

// Build the metAttributeTypes table.
// This used to be handled by the dump_attrs.py script.
-(void)buildAttributeTypes
{
    NSString *queryFormat = @"SELECT attributeID, unitID, iconID, displayName, attributeName FROM dgmAttributeTypes WHERE attributeID IN %@;";
    NSString *drones = @"(283,1271)";
    NSString *structure = @"(9,113,111,109,110)";
    NSString *armour = @"(265,267,268,269,270)";
    NSString *shield = @"(263,349,271,272,273,274,479)";
    NSString *capacitor = @"(482,55)";
    NSString *targeting = @"(76,192,208,209,210,211,552)";
    NSString *propulsion = @"(37)";;
    NSString *fitting = @"(12,13,14,101,102,1154,1547,1132,11,48)";
    
    char *errmsg;
    int rc;
    
    // First see if the table exists and has data in it. If so, return.
	NSInteger cnt = [self performCount:"SELECT COUNT(*) FROM metAttributeTypes;"];
    if( cnt > 0 )
        return;
    
    cnt = [self performCount:"SELECT count(*) FROM sqlite_master WHERE type='table' AND name='metAttributeTypes';;"];
    
	[self beginTransaction];
    
    /*
     rc = sqlite3_exec(db, "DROP TABLE IF EXISTS metAttributeTypes;", NULL, NULL, &errmsg);
     if(rc != SQLITE_OK)
     {
     [self logError:errmsg];
     [self rollbackTransaction];
     return;
     }
     */
    
    if( 0 == cnt )
    {
        rc = sqlite3_exec(db, "CREATE TABLE metAttributeTypes (attributeID INTEGER, unitID INTEGER, iconID INTEGER, displayName VARCHAR(100), attributeName VARCHAR(100), typeGroupID INTEGER);", NULL, NULL, &errmsg);
        if(rc != SQLITE_OK)
        {
            [self logError:errmsg];
            [self rollbackTransaction];
            return;
        }
    }
    
    [self insertAttributeTypes:[NSString stringWithFormat:queryFormat, drones] number:1];
    [self insertAttributeTypes:[NSString stringWithFormat:queryFormat, structure] number:2];
    [self insertAttributeTypes:[NSString stringWithFormat:queryFormat, armour] number:3];
    [self insertAttributeTypes:[NSString stringWithFormat:queryFormat, shield] number:4];
    [self insertAttributeTypes:[NSString stringWithFormat:queryFormat, capacitor] number:5];
    [self insertAttributeTypes:[NSString stringWithFormat:queryFormat, targeting] number:6];
    [self insertAttributeTypes:[NSString stringWithFormat:queryFormat, propulsion] number:7];
    [self insertAttributeTypes:[NSString stringWithFormat:queryFormat, fitting] number:9];
    
    NSString *otherAttributes = @"SELECT attributeID, unitID, iconID, displayName, attributeName "
    "FROM dgmAttributeTypes WHERE attributeID NOT IN "
    "(SELECT attributeID FROM metAttributeTypes);";
    [self insertAttributeTypes:otherAttributes number:8];
    
    [self commitTransaction];
}

-(NSInteger) performCount:(const char *)query
{
    sqlite3_stmt *countStatement;
    NSInteger rows = 0;
    int rc = sqlite3_prepare_v2( db, query, (int)strlen(query), &countStatement, NULL );
	if( rc != SQLITE_OK )
    {
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return 0;
	}
    
    if( sqlite3_step(countStatement) == SQLITE_ERROR )
    {
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return 0;
    }
    else
    {
        rows = sqlite3_column_nsint(countStatement, 0);
    }
    return rows;
}

-(void)buildTypePrerequisites
{
	int rc;
    NSString *typeIDQuery = @"SELECT typeID FROM invTypes where published = 1 AND groupID IN (SELECT groupID FROM invGroups WHERE categoryID IN (6,7,8,16));";
    sqlite3_stmt *typeIDStatement;
    //    NSString *skillQuery = @"SELECT taSkill.typeID, "
    //    "COALESCE(taSkill.valueInt,taSkill.valueFloat) as skillTypeID, "
    //    "COALESCE(taLevel.valueInt,taLevel.valueFloat) as skillLevel "
    //    "FROM "
    //    "dgmTypeAttributes taSkill JOIN dgmAttributeTypes atSkill ON (taSkill.attributeID = atSkill.attributeID), "
    //    "dgmTypeAttributes taLevel JOIN dgmAttributeTypes atLevel ON (taLevel.attributeID = atLevel.attributeID) "
    //    "WHERE taSkill.typeID = ? "
    //    "AND taSkill.typeID = taLevel.typeID "
    //    "AND atLevel.categoryID = atSkill.categoryID "
    //    "AND atSkill.attributeName GLOB \'requiredSkill[0-9]\' "
    //    "AND atLevel.attributeName GLOB \'requiredSkill[0-9]Level\' "
    //    "AND atLevel.attributeName GLOB atSkill.attributeName;";
    NSString *skillQuery = @"SELECT taSkill.typeID, "
    "COALESCE(taSkill.valueInt,taSkill.valueFloat) as skillTypeID, "
    "COALESCE(taLevel.valueInt,taLevel.valueFloat) as skillLevel, "
    "atLevel.attributeName, atSkill.attributeName "
    "FROM "
    "dgmTypeAttributes taSkill JOIN dgmAttributeTypes atSkill ON (taSkill.attributeID = atSkill.attributeID), "
    "dgmTypeAttributes taLevel JOIN dgmAttributeTypes atLevel ON (taLevel.attributeID = atLevel.attributeID) "
    "WHERE taSkill.typeID = ? "
    "AND taSkill.typeID = taLevel.typeID "
    "AND atLevel.categoryID = atSkill.categoryID "
    "AND atSkill.attributeName GLOB \'requiredSkill[0-9]\' "
    "AND atLevel.attributeName GLOB \'requiredSkill[0-9]Level\' ";
    sqlite3_stmt *skillStatement;
    
    NSInteger cnt = [self performCount:"SELECT COUNT(*) FROM typePrerequisites;"];
    if( cnt > 0 )
        return;
    
	rc = sqlite3_prepare_v2( db, [typeIDQuery UTF8String], (int)[typeIDQuery length], &typeIDStatement, NULL );
	if( rc != SQLITE_OK )
    {
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return;
	}
    
	rc = sqlite3_prepare_v2( db, [skillQuery UTF8String], (int)[skillQuery length], &skillStatement, NULL );
	if( rc != SQLITE_OK )
    {
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
        sqlite3_finalize(typeIDStatement);
		return;
	}
    
    const char insert_attr[] = "INSERT INTO typePrerequisites VALUES (?,?,?,?);";
    sqlite3_stmt *insert_attr_stmt;
    rc = sqlite3_prepare_v2( db, insert_attr, (int)sizeof(insert_attr), &insert_attr_stmt, NULL);
    if( rc != SQLITE_OK )
    {
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
        sqlite3_finalize(typeIDStatement);
        sqlite3_finalize(skillStatement);
		return;
	}
    
    [self beginTransaction];
    
    int cntID = 0;
	while( sqlite3_step(typeIDStatement) == SQLITE_ROW )
    {
		NSInteger typeID = sqlite3_column_nsint(typeIDStatement,0);
        
        if( !(cntID++ % 100) )
        {
            NSLog( @"typeID count %d, insert Count %ld", cntID, [self performCount:"SELECT COUNT(*) FROM typePrerequisites;"] );
        }
        
        rc = sqlite3_bind_nsint( skillStatement, 1, typeID );
        
        int i = 0;
        while( sqlite3_step(skillStatement) == SQLITE_ROW )
        {
            NSString *levelAttributeName = sqlite3_column_nsstr(skillStatement,3);
            NSString *skillAttributeName = sqlite3_column_nsstr(skillStatement,4);
            NSComparisonResult res = [levelAttributeName compare:skillAttributeName options:NSCaseInsensitiveSearch range:NSMakeRange(0, [skillAttributeName length])];
            if( NSOrderedSame != res )
                continue;
            
            NSInteger typeID2 = sqlite3_column_nsint(skillStatement,0);
            NSInteger skillTypeID = sqlite3_column_nsint(skillStatement,1);
            NSInteger skillLevel = sqlite3_column_nsint(skillStatement,2);
            
            rc = sqlite3_bind_nsint( insert_attr_stmt, 1, typeID2 );
            rc = sqlite3_bind_nsint( insert_attr_stmt, 2, skillTypeID );
            rc = sqlite3_bind_nsint( insert_attr_stmt, 3, skillLevel );
            rc = sqlite3_bind_nsint( insert_attr_stmt, 4, i );
            
            if( (rc = sqlite3_step(insert_attr_stmt)) != SQLITE_DONE )
            {
                NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
                [self rollbackTransaction];
                sqlite3_finalize(insert_attr_stmt);
                sqlite3_finalize(skillStatement);
                sqlite3_finalize(typeIDStatement);
               return;
            }
            ++i;
            sqlite3_reset(insert_attr_stmt);
            //sqlite3_clear_bindings(insert_attr_stmt);
        }
        
        sqlite3_reset(skillStatement);
        sqlite3_clear_bindings(skillStatement);
	}
    
    sqlite3_finalize(insert_attr_stmt);
    sqlite3_finalize(skillStatement);
	sqlite3_finalize(typeIDStatement);
    
    [self commitTransaction];
    
	return;
}

- (void)insertStationID:(NSUInteger)stationID name:(NSString *)stationName system:(NSUInteger)solarSystemID
{
//    insert or replace into Book (Name, TypeID, Level, Seen) values ( ... )
    
    const char insert_attr[] = "INSERT OR REPLACE INTO metStations (stationID, solarSystemID, stationName) VALUES (?,?,?)";
    sqlite3_stmt *insert_attr_stmt;
    
    int rc = sqlite3_prepare_v2( db, insert_attr, (int)sizeof(insert_attr), &insert_attr_stmt, NULL);
    if( rc != SQLITE_OK )
    {
		NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return;
	}

	rc = sqlite3_bind_nsint( insert_attr_stmt, 1, stationID );
    rc = sqlite3_bind_nsint( insert_attr_stmt, 2, solarSystemID );
    rc = sqlite3_bind_text( insert_attr_stmt, 3, [stationName UTF8String], (int)[stationName length], NULL );
    
    if( (rc = sqlite3_step(insert_attr_stmt)) != SQLITE_DONE )
    {
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
    }
    
    sqlite3_finalize(insert_attr_stmt);
}

// @"name", @"stationID" and @"systemID" are the keys in the dictionary
- (NSDictionary *) stationForID:(NSInteger)stationID
{
    // first make sure the staStation table exists
	const char query[] =
    "SELECT stationName, solarSystemID "
    "FROM metStations "
    "WHERE stationID = ?;";
	sqlite3_stmt *read_stmt;
	int rc;
	
	rc = sqlite3_prepare_v2(db,query,(int)sizeof(query),&read_stmt,NULL);
	if(rc != SQLITE_OK){
        NSLog( @"%s: sqlite error: %s", __func__, sqlite3_errmsg(db) );
		return nil;
	}
	
	NSMutableDictionary *staDict = [[[NSMutableDictionary alloc]init]autorelease];
	
	sqlite3_bind_nsint(read_stmt,1,stationID);
	
	while(sqlite3_step(read_stmt) == SQLITE_ROW)
    {
		
		NSInteger systemID = sqlite3_column_nsint(read_stmt,1);
		NSString *stationName = sqlite3_column_nsstr(read_stmt,0);
		
		[staDict setObject:stationName forKey:@"name"];
		[staDict setObject:[NSNumber numberWithInteger:systemID] forKey:@"systemID"];
		[staDict setObject:[NSNumber numberWithInteger:stationID] forKey:@"stationID"];
	}
	
	sqlite3_finalize(read_stmt);
	
	return staDict;
}

@end
