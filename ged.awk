#!/usr/bin/awk -f
# Take output from a ged file and convert it into a few different possible
# ways of looking at the data
# 
# Look for lines that start with 0, then @Pn<nn>@
# Somewhere after that, before the next line that starts with 0,
# will be a line with "1 NAME First /Last/"

# Input is
# Each line starts with an indent and a field
# 
# There are IDs: @xxxx@
# individuals, sources, families
#
# A typical line has the indent level, a type indicator, and data
# Some type indicators do not have data, but instead have lines of data
# 
# The level zero lines are 0 @id@ TYPE
#
# level 0 types are INDI, FAM, SOUR, HEAD, REPO
# There is only one HEAD and one REPO, which is meta-data
#
# Samples 
# 0 @P2@ INDI
# 1 BIRT
# 2 DATE 5 Jul 1938
# 2 SOUR @S1127979882@
# 3 _APID 1,1788::28070653
# 1 NAME Joan Linda /Walters/
# 1 SEX F
# 1 FAMC @F15@
# 1 FAMS @F2@  
# 
# 0 HEAD
#   1 CHAR
#   1 SOUR
#     2 VERS
#     2 NAME
#     2 CORP
#   1 GEDC
#     2 VERS
#     2 FORM
# 0 @Pid@ INDI
#   1 BIRT
#     2 DATE
#     2 PLAC
#     2 SOUR @id@
#       3 PAGE
#         4 CONC
#       3 _APID
#   1 SEX
#   1 NAME Firsts Middles /Lasts/ Suffixes
#   1 FAMC
#   1 FAMS  [can be multiple FAMS records per person]
#   1 RESI
#     2 DATE
#     2 PLAC
#     2 SOUR @id@
#       3 _APID
#   1 OBJE
#     2 FILE
#     2 FORM
#     2 TITL
#   1 DEAT
#     2 DATE
#     2 PLAC
#   1 SOUR
#     2 PAGE
#     2 DATA
#       3 TEXT
#   1 BURI
# 0 @Fid@ FAM
#   1 HUSB @Pid@
#   1 WIFE @Pid@
#   1 MARR
#     2 DATE
#     2 PLAC
#     2 SOUR @Sid@
#       3 PAGE
#       3 _APID
#   1 CHIL @Pid@
#     2 _FREL Unknown  <Father's relationship>
#     2 _MREL Natural  <Mother's relationship>
# 0 @Rid@ REPO
#   1 NAME
# 0 @Sid@ SOUR
#   1 REPO
#   1 TITL
#   1 AUTH
#   1 PUBL
#   1 _APID
# 0 TRLR
#
# As we read things in, we store them in a set of arrays.
# name[id]
# sex[id]
# famc[id] - the family ID of the family where this person is a child
# arrival[id] 
# eventplace[type,id]
# eventdate[type,id]
#
# This next set is derived from the above
# eventtrack[type,id] - this is the country in Europe or state/province in NA
# eventcontinent[type,id] - determined based on the eventtrack
# eventlocal[type,id] - the part of the place before the state/country
# eventyear[type,id] - parsed out of the eventdate

function blocal(id)
{
    return eventlocal["BIRT,"id]
}

function bplace(id)
{
    return eventplace["BIRT,"id]
}

function dplace(id)
{
    return eventplace["DEAT,"id]
}

function btrack(id)
{
    return eventtrack["BIRT,"id]
}

function dtrack(id)
{
    return eventtrack["DEAT,"id]
}

function byear(id)
{
    return eventyear["BIRT,"id]
}

function dyear(id)
{
    return eventyear["DEAT,"id]
}

function diedCont(id)
{
    return eventcontinent["DEAT,"id]
}

function bornCont(id)
{
    return eventcontinent["BIRT,"id]
}

function continentOf(country)
{
    if (length(continent[country])>0)
	return continent[country]
    print "Unknown continent for country: " country
    return "UNKNOWN"
}

function isCountry(place)
{
    if (locationType[toupper(place)] == "country")
	return 1
    return 0
}

function isCanadianProvince(place)
{
    if (locationType[toupper(place)] == "province")
	return 1
    return 0
}

function isNAState(place)
{
    if ((locationType[toupper(place)] == "state") || 
	(locationType[toupper(place)] == "province"))
	return 1
    return 0
}

# could ignore trailing question marks

function year(bd,   possible)
{
    if (match(bd,/^[1][0-9][0-9][0-9]/))
	return substr(bd, RSTART, RLENGTH)

    if (match(bd,/[12][0-9][0-9][0-9][ ?]*$/))
    {
	possible = substr(bd, RSTART, RLENGTH)
	if ((earliest_year < possible) && (possible < latest_year))
	    return possible
	else
	    return 0
    }
    return 0
}

function iSpace(level,   i, s)
{
    s = ""
    i = level
    while (i--)
	s = " " s
    return s
}

function count(path,  t, r, l)
{
    r = path
    t = 0
    l = 0
    while (length(r)>0)
    {
	t *= 2
	if (substr(r,1,1) == "2")
	    t++
	r = substr(r,2,length(r)-1)
    }
    return t
}

# location = "Canonical Name, type(state/province/country), continent, 
#             order in key, color, alt name1, alt name2, etc"

# For any given country/state, we want to know
# Canonical form, abbreviation, continent, is it a country/state, what 
# order to print it in the key, what color to make it, and what are the
# other ways someone might write it.
#
# possible simplifying assumptions: upper case everything. Remove punctuation
# and spaces. Replace accented characters with the non-accented version.
#
# Also could shorten the words for state and the name of the continent
#
function init()
{
    i = 1

    continentEnum["E"] = "Europe"
    continentEnum["N"] = "North America"
    continentEnum["A"] = "Asia"
    locationTypeEnum["s"] = "state"
    locationTypeEnum["p"] = "province"
    locationTypeEnum["c"] = "country"
    locationTypeEnum["t"] = "continent"
    US = "US"
    Alabama = "Alabama"
    Alaska = "Alaska"
    Arizona = "Arizona"
    Arkansas = "Arkansas"
    California = "California"
    Colorado = "Colorado"
    Connecticut = "Connecticut"
    Delaware = "Delaware"
    Florida = "Florida"
    Georgia = "Georgia"
    Hawaii = "Hawaii"
    Idaho = "Idaho"
    Illinois = "Illinois"
    Indiana = "Indiana"
    Iowa = "Iowa"
    Kansas = "Kansas"
    Kentucky = "Kentucky"
    Louisiana = "Louisiana"
    Maine = "Maine"
    Maryland = "Maryland"
    Massachusetts = "Massachusetts"
    Michigan = "Michigan"
    Minnesota = "Minnesota"
    Mississippi = "Mississippi"
    Missouri = "Missouri"
    Montana = "Montana"
    Nebraska = "Nebraska"
    Nevada = "Nevada"
    NewHampshire = "New Hampshire"
    NewJersey = "New Jersey"
    NewMexico = "New Mexico"
    NewYork = "New York"
    NorthCarolina = "North Carolina"
    NorthDakota = "North Dakota"
    Ohio = "Ohio"
    Oklahoma = "Oklahoma"
    Oregon = "Oregon"
    Pennsylvania = "Pennsylvania"
    RhodeIsland = "Rhode Island"
    SouthCarolina = "South Carolina"
    SouthDakota = "South Dakota"
    Tennessee = "Tennessee"
    Texas = "Texas"
    Utah = "Utah"
    Vermont = "Vermont"
    Virginia = "Virginia"
    Washington = "Washington"
    WestVirginia = "West Virginia"
    Wisconsin = "Wisconsin"
    Wyoming = "Wyoming"
    Austria = "Austria"
    Barbados = "Barbados"
    Belgium = "Belgium"
    Canada = "Canada"
    Czechia = "Czechia"
    Denmark = "Denmark"
    England = "England"
    Finland = "Finland"
    France = "France"
    Germany = "Germany"
    Haiti = "Haiti"
    Ireland = "Ireland"
    Italy = "Italy"
    Japan = "Japan"
    Jamaica = "Jamaica"
    Mexico = "Mexico"
    NativeAmerica = "Native America"
    Netherlands = "Netherlands"
    NorthernIreland = "Northern Ireland"
    Norway = "Norway"
    Pakistan = "Pakistan"
    Romania = "Romania"
    Scotland = "Scotland"
    Switzerland = "Switzerland"
    Slovenia = "Slovenia"
    Sweden = "Sweden"
    Wales = "Wales"
    Yugoslavia = "Yugoslavia"
    Quebec = "Quebec"
    Ontario = "Ontario"
    NewBrunswick = "New Brunswick"
    NovaScotia = "Nova Scotia"
    AncestorOfEurope = "Ancestor of Europe"
    AncestorOfNA = "Ancestor of state/province"
    Unknown = "Unknown"

    loc[i++] = US ", US, c, N, none, none, United States, America, The Colonies, United States of America, United States ?, British Colonial America, USA, USA ?, U.S.A., Colonial America, British America, British Colonies, New Netherlands, Amer. Col., usa., U.S.A, American Colony, Amer. Col"
    loc[i++] = Alabama ", AL, s, N, mediumpurple, xx"
    loc[i++] = Alaska ", AK, s, N, blue, xx"
    loc[i++] = Arizona ", AZ, s, N, blue, xx"
    loc[i++] = Arkansas ", AR, s, N, blue, xx"
    loc[i++] = California ", CA, s, N, blue, xx"
    loc[i++] = Colorado ", CO, s, N, blue, xx"
    loc[i++] = Connecticut ", CT, s, N, mediumseagreen, Ct, Connecticut., Conn, CT., Connectitcut"
    loc[i++] = Delaware ", DE, s, N, paleturquoise, xx"
    loc[i++] = Florida ", FL, s, N, blue, xx"
    loc[i++] = Georgia ", GA, s, N, blue, xx"
    loc[i++] = Hawaii ", HI, s, N, blue, xx"
    loc[i++] = Idaho ", ID, s, N, blue, xx"
    loc[i++] = Illinois ", IL, s, N, blue, xx"
    loc[i++] = Indiana ", IN, s, N, blue, xx"
    loc[i++] = Iowa ", IO, s, N, blue, xx"
    loc[i++] = Kansas ", KS, s, N, blue, xx"
    loc[i++] = Kentucky ", KY, s, N, blue, xx"
    loc[i++] = Louisiana ", LA, s, N, blue, La., louisiana, La, Orleans Territory"
    loc[i++] = Maine ", ME, s, N, lime, xx"
    loc[i++] = Maryland ", MD, s, N, powderblue, xx, Md"
    loc[i++] = Massachusetts ", MA, s, N, greenyellow, Mass, MBC, Massachusets, Massachusetts Bay Colony, Province of Massachusetts Bay, Massachusetts. USA, Massachusetts Bay, Mass., Massachusettes"
    loc[i++] = Michigan ", MI, s, N, orange, Michigan., Mich"
    loc[i++] = Minnesota ", MN, s, N, blue, Minn"
    loc[i++] = Mississippi ", MS, s, N, blue, xx"
    loc[i++] = Missouri ", MO, s, N, blue, xx"
    loc[i++] = Montana ", MT, s, N, blue, xx"
    loc[i++] = Nebraska ", NE, s, N, thistle, xx"
    loc[i++] = Nevada ", NV, s, N, blue, xx"
    loc[i++] = NewHampshire ", NH, s, N, limegreen, xx"
    loc[i++] = NewJersey ", NJ, s, N, deepskyblue, Colony of New Jersey"
    loc[i++] = NewMexico ", NM, s, N, blue, xx"
    loc[i++] = NewYork ", NY, s, N, aqua, Province of New York, New Netherlands, N Y"
    loc[i++] = NorthCarolina ", NC, s, N, slateblue, xx"
    loc[i++] = NorthDakota ", ND, s, N, blue, xx"
    loc[i++] = Ohio ", OH, s, N, indianred, xx"
    loc[i++] = Oklahoma ", OK, s, N, blue, xx"
    loc[i++] = Oregon ", OR, s, N, blue, xx"
    loc[i++] = Pennsylvania ", PA, s, N, blue, Pa, Pa., Pennsylvania USA, Penna, PA., Penn"
    loc[i++] = RhodeIsland ", RI, s, N, green, Rhode Island Colony"
    loc[i++] = SouthCarolina ", SC, s, N, blue, xx, So Carolina"
    loc[i++] = SouthDakota ", SD, s, N, blue, xx"
    loc[i++] = Tennessee ", TN, s, N, indigo, xx"
    loc[i++] = Texas ", TX, s, N, blueviolet, xx"
    loc[i++] = Utah ", UT, s, N, violet, Ut, Utah Territory"
    loc[i++] = Vermont ", VT, s, N, mediumspringgreen, vermont"
    loc[i++] = Virginia ", VA, s, N, dodgerblue, Virginia Colony, Colony of Virginia, Va"
    loc[i++] = Washington ", WA, s, N, blue, xx"
    loc[i++] = WestVirginia ", WV, s, N, white, xx, WVA"
    loc[i++] = Wisconsin ", WI, s, N, lightsalmon, Wisconsin., Wis"
    loc[i++] = Wyoming ", WY, s, N, blue, xx"
    loc[i++] = Austria ", AT, c, E, none, xx"
    loc[i++] = Barbados ", BA, c, E, none, xx"
    loc[i++] = Belgium ", BE, c, E, peru, Belgique"
    loc[i++] = Canada ", CD, c, N, none, British Canada, Can, CANADA, Cn, CND, Canada., Canadaa, Cananda, Canda"
    loc[i++] = Czechia ", CZ, c, E, none, Czech Republic"
    loc[i++] = England ", EN, c, E, yellow, ENGLAND, england, ENG, Eng, EN, En, United Kingdom, UK, prob. England"
# France was moccasin
    loc[i++] = France ", FR, c, E, silver, FRANCE, france, Fra, Fr, Malta or France"
# Germany was gold
    loc[i++] = Germany ", GE, c, E, magenta, Deutschland, Ger., Ger, GE, Grmn, Wuerttemberg, Nellingen, Nellingen?, Asselfingen, Prussia, Pomerania"
    loc[i++] = Haiti ", HT, c, N, none, xx"
    loc[i++] = Italy ", IT, c, E, none, Regno d'Italia"
    loc[i++] = Japan ", JP, c, A, none, xx"
    loc[i++] = Jamaica ", JM, c, A, none, xx"
    loc[i++] = Mexico ", MX, c, A, none, México"
# Netherlands was peachpuff
    loc[i++] = Netherlands ", NL, c, E, darkorange, Nederlands, Nederland"
    loc[i++] = Wales ", WL, c, E, papayawhip, xx"
    loc[i++] = Pakistan ", PK, c, E, gold, Pak"
    loc[i++] = Romania ", RO, c, E, gold, BUK"
    loc[i++] = Scotland ", SL, c, E, khaki, xx"
    loc[i++] = Switzerland ", CH, c, E, gold, Swtz, Switz, Swtz., Suisse"
    loc[i++] = Slovenia ", SN, c, E, gold, xx"
    loc[i++] = Yugoslavia ", YG, c, E, gold, xx"
    loc[i++] = Finland ", FI, c, E, gold, xx"
    loc[i++] = Norway ", NO, c, E, gold, xx"
    loc[i++] = Sweden ", SE, c, E, gold, xx"
    loc[i++] = Denmark ", DK, c, E, gold, xx"
    loc[i++] = NativeAmerica ", NA, c, N, black, xx"
    loc[i++] = NorthernIreland ", NI, c, E, palegoldenrod, xx"
    loc[i++] = Ireland ", IE, c, E, lightgoldenrodyellow, xx"
    loc[i++] = Quebec ", QC, p, N, red, New France, Qc, Qu, Quebec. Canada, Que, Nouvelle France, Nouvelle-France, Province of Quebec, PQ, P.Q., Pq, Québec, Lower Canada (Québec), Canada French, (Nouvelle-France)"
    loc[i++] = Ontario ", ON, p, N, coral, Ont., Ont"
    loc[i++] = NewBrunswick ", NB, p, N, salmon, xx"
    loc[i++] = NovaScotia ", NS, p, N, crimson, Ns, Acadie, Acadia"
    loc[i++] = AncestorOfEurope ", AE, t, E, lavender, xx"
    loc[i++] = AncestorOfNA ", AN, t, N, white"
    loc[i++] = Unknown ", UN, t, E, gainsboro"

    keyLines = NewHampshire "," Vermont "," Massachusetts "," Connecticut "," RhodeIsland "," NewYork "," Pennsylvania "," NewJersey "," Delaware "," Maryland "," Virginia "," Ohio "," Michigan "," Utah "," Texas "," Ontario "," Quebec "," NewBrunswick "," NovaScotia "," NativeAmerica "," England "," Wales "," Scotland "," NorthernIreland "," Ireland "," France "," Netherlands "," Germany "," Switzerland "," AncestorOfNA "," AncestorOfEurope

    trackingStates = split(keyLines,countryOfKeyOrder,",")

    for (j in loc)
    {
	k = 2
	numEntries = split(loc[j],places,", ")

# start with the second item, which is the abbreviation for printing
	abbreviation[places[1]] = places[k++]

# is it a country, state, or province?
	locationType[toupper(places[1])] = locationTypeEnum[places[k++]]

# what continent is it on?
	continent[places[1]] = continentEnum[places[k++]]

# what color will we use?
	colorOf[places[1]] = places[k++]

# remember the canonical name for the name, abbreviation and any other forms
	canonical[toupper(places[1])] = places[1]
	canonical[toupper(places[2])] = places[1]
	while (k <= numEntries)
	    canonical[toupper(places[k++])] = places[1]
    }
    defaultLocality[Quebec] = "Quebec"
    defaultLocality[NovaScotia] = "Annapolis Royal"
    defaultLocality[Pennsylvania] = "Philadelphia"
}

#
# Return true if we want to print this person out as part of the Canada line.
# This would be if the id or any of its ancestors were born in Canada,
# or a few others in North America who had a Canadian descendant.
#
function isCanada(id)
{
    if (length(id) && 
	((eventcountry["BIRT,"id]==Canada)||(eventcountry["DEAT,"id]==Canada)||
	 ((mark[id,"CanAnc"]==1) && 
	  (diedCont(id)=="North America")) ||
	 (isCanada(wife[famc[id]])) || (isCanada(husband[famc[id]]))))
	return 1
    else
	return 0
}
#
# Return true if we want to print this person as part of the tree in America
#
function isAmerica(id)
{
    if (length(id) && 
	((bornCont(id) == "North America") || 
	 (diedCont(id) == "North America")))
	return 1
    else
	return 0
}

function clearList()
{
    numberInList = 0
    for (i=0;i<maxList;i++)
	checkList[i] = ""
}

function buildList(id, levels)
{
#    print "buildList(" id ", " levels ")"
    if (levels == 1)
    {
#	print "So far there are " numberInList " items in list"
	if (length(husband[famc[id]]) > 0)
	{
	    checkList[numberInList++] = husband[famc[id]]
#	    print "Added to list"
	}
	if (length(wife[famc[id]]) > 0)
	{
	    checkList[numberInList++] = wife[famc[id]]
#	    print "Added to list"
	}
	if (numberInList > maxList)
	    maxList = numberInList
    }
    else
    {
	buildList(husband[famc[id]], levels-1)
	buildList(wife[famc[id]], levels-1)
    }
}

function matchList(id, levels,   i, rv)
{
#    print "matchList(" id ", " levels ")"
    if (levels == 0)
    {
	rv = 0
	for (i=0;i<numberInList;i++)
	{
#	    print "Checking " id " against " checkList[i]
	    if (id == checkList[i])
	    {
		rv = 1
		print id " " name[id] " had " cousinDegree-1 "-great grandchildren who got married"
	    }
	}
	return rv
    }
    else 
	return (matchList(husband[famc[id]],levels-1) || 
		matchList(wife[famc[id]],levels-1))
}

function findCousins(id, N,     mother, father, mgm, pgm)
{
#    print "findCousins " id ", " N
    if (length(id) == 0)
	return

# Man 1 and Woman 2 are cousins of degree N (either half or full or more)
# if ancestors at level N+1 match.
# Starting with a child in the family, it would be level N+2
# Your parents are first cousins if any of your dad's grandparents match
# any of your mom's grandparents.

    clearList()
    buildList(husband[famc[id]], N+1)
    if (matchList(wife[famc[id]], N+1))
	print id " " name[id] " " byear(id) " had parents who were " N "-degree cousins"
    
    findCousins(husband[famc[id]], N)
    findCousins(wife[famc[id]], N)
}

function markAncestors(id, testFor, descendantValue)
{
    if (length(id) == 0)
	return 0
    if (descendantValue == 1)
    {
	mark[id","testFor] = 1
	markAncestors(husband[famc[id]], testFor, 1)
	markAncestors(wife[famc[id]], testFor, 1)
    }
    if (testFor == "CanAnc")
    {
	if (eventcountry["BIRT,"id] == Canada)
	{
	    mark[id,testFor] = 1
	    markAncestors(husband[famc[id]], testFor, 1)
	    markAncestors(wife[famc[id]], testFor, 1)
	}
	else
	{
	    markAncestors(husband[famc[id]], testFor, 0)
	    markAncestors(wife[famc[id]], testFor, 0)
	}
    }
}

function color(place,    homeland)
{
    if (place ~ "ancestor of")
    {
	homeland = substr(place, 13, length(place) - 12)
	if (isNAState(homeland))
	    return colorOf[AncestorOfNA]
	else
	    return colorOf[AncestorOfEurope]
    }
    if (length(colorOf[place]) > 0)
	return colorOf[place]
    else
	return colorOf[Unknown]
}

function printfams(fid,     i)
{
    if (length(fid) == 0)
	return
    printf("%s|%s|%s|%s|%d",fid,husband[fid],wife[fid],marrDate[fid],kids[fid])
    for (i = 1; i<=kids[fid]; i++)
	printf("|%s",childOf[fid","i])
    printf("\n")
    printfams(famc[husband[fid]])
    printfams(famc[wife[fid]])
}

function kidsOf(id,   i, rv)
{
    rv = 0
    for (i = 1; i <= numberOfFams[id]; i++)
	rv += kids[fams[id","i]]
    return rv
}

function printfamheader()
{
    printf("level|id|name[id]|sex|btrack(id)|bplace(id)|byear(id)|dtrack(id)|dplace(id)|dyear(id)|ageAtDeath[id]|famc[id]|wife[famc[id]]|husband[famc[id]]|agem[id]|agef[id]|kids[famc[id]]|halfsibs[id]|totalsibs[id]|birthorder(id)|numberOfFams[id]|fams[id,1]|fams[id,2]|kidsOf(id)|ageFirstChild(id)|ageLastChild(id)|ageFirstMarriage(id)|Sib 1 child[famc[id],1]|sib 2 child[famc[id],2]|Sib 3 child[famc[id],3]\n")
}

#
# level: how many levels of ancestors are we at? Used to print and to 
# maxl     : prevent us from going too deep
# path: the list of 122112 (Father = 1, Mother = 2)
# id: id in the database
# ancestralBirth: in case there is no record where this person is born
# ancestorName: in case we want to print this person as "Ancestor of X"
# includeMissing: whether we want to print a line for people we don't know
#                 we might do this to show blank circles on a screen, e.g.
# printType: "Color" - print javascript code to show this person in color
#
#            anything else - print the name, indented
#            specific types include
#                 Canada: print if the person is in the Canada part of the tree
#                         meaning they were born or died in Canada, or if they
#                         died in NA and were an ancestor of Canadians, or if
#                         their spouse was one of those.
#                 Immigrant: print if they were from Europe and died in N.A.
#                 IDs: Count how many times a person appears in the tree
#                 Anything else: just print everyone
#
function printfam(level, maxl, path, id, ancestralBirth, ancestorName, includeMissing, printType, test,    placeToPass, placeToPrint, nameToPass, nameToPrint, idToPass)
{
    if (((length(id) == 0) && (includeMissing == 0)) || (level > maxl))
	return 0

    if (length(btrack(id)) > 0)
    {
	placeToPass = btrack(id)
	placeToPrint = btrack(id)
    }
    else
    {
	placeToPass = ancestralBirth
	placeToPrint = "ancestor of " ancestralBirth
    }
    if (length(name[id]) > 0)
    {
	nameToPass = name[id]
	nameToPrint = name[id]
    }
    else
    {
	nameToPass = ancestorName
	nameToPrint = "ancestor of " ancestorName
    }
    if (length(arrival[id]) > 0)
	arrivalString = "Arv:" arrival[id] "->"
    else
	arrivalString = ""

    # We can put a mark at the front of the line, such as using an asterisk
    # to indicate which people are common ancestors of another descendant
    printMark = " "
    if (mark[id,test] == 1)
	printMark = "*"

    if (printType == "Color")
    {
	# Get rid of any double quotes or slashes in the name
        gsub(/"/, "'", nameToPrint)
	gsub(/\//, "", nameToPrint)

	# Need to put out javascript that sets the color for this person's spot
	# The text to show when hovering over the spot
	# And whether or not they are an immigrant (for thicker borders)

	# Only going to use a particular country color for people in NA
	if ((bornCont(id) == "North America") || 
	    (diedCont(id) == "North America"))
	{
	    if (bornCont(id) == "Europe")
		immigrant = 1
	    else
		immigrant = 0
	    printf("country[%d][%d]='%s'\n", level, count(path), color(placeToPrint));
	    printf("text[%d][%d]=\"%s, born %s %s\"\n", level, count(path), nameToPrint, eventdate["BIRT,"id], placeToPrint);
	    printf("immigrant[%d][%d]=%d\n", level, count(path), immigrant);
	}
	else
	{
	    if ((bornCont(id) == "Europe") ||
		(continentOf(ancestralBirth) == "Europe"))
		colorToPrint = color(AncestorOfEurope)
	    else
		colorToPrint = color(AncestorOfNA)
		
	    printf("country[%d][%d]='%s'\n", level, count(path), colorToPrint);
	    printf("text[%d][%d]='%s'\n", level, count(path), placeToPrint);
	    printf("immigrant[%d][%d]=%d\n", level, count(path), 0);
	}
    }
    else if (printType == "Canada")
    {
	if ((isCanada(id)))
# This test is for possible Filles du roi
#	    && (byear(id)<1660) && (dyear(id)>1663) && (sex[id]=="F") &&
#	    (eventcountry["BIRT,"id] == "France") && 
##          eventtrack["DEAT,"id] == "Quebec"))
	{
	    bpstring = abbreviation[placeToPrint]
	    if (length(bpstring)>0)
		bpstring = " " bpstring
	    printf("%s%s%d %s %s%s->%s%s %s\n", printMark, iSpace(level), level, name[id], byear(id), bpstring, arrivalString, dyear(id), abbreviation[eventtrack["DEAT,"id]])
	}
    }
    else if (printType == "America")
    {
	if ((isAmerica(id)))
	{
	    bpstring = abbreviation[placeToPrint]
	    if (length(bpstring)>0)
		bpstring = " " bpstring
	    printf("%s%s%d %s %s%s->%s%s %s\n", printMark, iSpace(level), level, name[id], byear(id), bpstring, arrivalString, dyear(id), abbreviation[eventtrack["DEAT,"id]])
	}
    }
    else if (printType == "Immigrant")
    {
	if ((bornCont(id) == "Europe") && 
	    (diedCont(id) == "North America"))
	{
	    printf("%s%d %s %s %s->%s%s %s\n", iSpace(level), level, name[id], byear(id), abbreviation[placeToPrint], arrivalString, dyear(id), abbreviation[eventtrack["DEAT,"id]])
	}
    }
    else if (printType == "IDs")
    {
	if (length(id) > 0)
	{
	    countAppearances[id]++
	    printf("%s Count:%d %s\n", id, countAppearances[id], name[id])
	}
    }
    else if (printType == "Dump")
    {
	printf("%d|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d|%d|%d|%d|%d|%d|%d|%s|%s|%d|%d|%d|%d|%s|%s|%s\n",level,id,name[id],sex[id],btrack(id),bplace(id),byear(id),dtrack(id),dplace(id),dyear(id),ageAtDeath[id],famc[id],wife[famc[id]],husband[famc[id]],agem[id],agef[id],kids[famc[id]],halfsibs[id],totalsibs[id],birthorder(id),numberOfFams[id],fams[id","1],fams[id","2],kidsOf(id),ageFirstChild(id),ageLastChild(id),ageFirstMarriage(id),child[famc[id]","1],child[famc[id]","2],child[famc[id]","3])
    }
    else
	printf("%s%s%d %s %s %s\n", printMark, iSpace(level), level, name[id], byear(id), btrack(id))
#	printf("%s%s%d %s %s %s\n", printMark, iSpace(level), level, name[id], byear(id), placeToPrint)

    if (famc[id] ~ /@/)
    {
	Print "id is " id " and famc[id] is " famc[id]
	if (husband[famc[id]] ~ /@/)
	    idToPass = husband[famc[id]]
	else
	    idToPass = ""
	printfam(level+1, maxl, (path "1"), idToPass,
		 placeToPass, nameToPass, includeMissing, printType, test);
	if (wife[famc[id]] ~ /@/)
	    idToPass = wife[famc[id]]
	else
	    idToPass = ""
	printfam(level+1, maxl, (path "2"), idToPass,
		 placeToPass, nameToPass, includeMissing, printType, test);
    }
    else
    {
	printfam(level+1, maxl, (path "1"), "",
		 placeToPass, nameToPass, includeMissing, printType, test);
	printfam(level+1, maxl, (path "2"), "",
		 placeToPass, nameToPass, includeMissing, printType, test);
    }
}

function printID(id)
{
    if ((length(byear(id)) > 0) && (length(dyear(id)) > 0) &&
	(printed[id] != 1) && (mark[id",Bart"] != 1))
    {				   
	printf("%s|%s|%d|%d|%d\n",id,name[id],byear(id),dyear(id),dyear(id)-byear(id))
	printed[id] = 1
    }
}

function printIDandKids(id,   f, k)
{
    printID(id)
    for (f = 1; f <= numberOfFams[id]; f++)
	for (k = 1; k <= kids[fams[id","f]]; k++)
	{
	    printID(child[fams[id","f]","k])
	}
}

function dumpTreePlusChildren(id)
{
    if (length(id) == 0)
	return
    printIDandKids(id)
    dumpTreePlusChildren(husband[famc[id]])
    dumpTreePlusChildren(wife[famc[id]])
}

function standardASCII(locality)
{
    rString = locality
    gsub(/é/, "e", rString)    
    gsub(/è/, "e", rString)    
    gsub(/Î/, "I", rString)
    gsub(/ô/, "o", rString)
    gsub(/ç/, "c", rString)
    gsub(/ê/, "e", rString)
    gsub(/â/, "a", rString)
    gsub(/É/, "E", rString)
    gsub(/ü/, "u", rString)
    return rString
}

function cleanlocality(id, event)
{
    if (eventlocal[event","id] == "")
	eventlocal[event","id] = defaultLocality[eventtrack[event","id]]
    eventlocal[event","id] = standardASCII(eventlocal[event","id])

    # Remove anything like ",1234567"
    gsub(/[,]*[0-9][0-9][0-9][0-9][0-9][0-9][0-9]/, "", eventlocal[event","id])
    gsub(/likely/, "", eventlocal[event","id])

    # Remove any province names that seem problematic
    gsub(/,Alsace/, "", eventlocal[event","id])
    gsub(/,Acadia/, "", eventlocal[event","id])

    gsub(/,Northern Alsace$/, "", eventlocal[event","id])
    gsub(/,Franche-Comte$/, "", eventlocal[event","id])
    gsub(/,Champagne-Ardenne$/, "", eventlocal[event","id])
    gsub(/,Normandie$/, "", eventlocal[event","id])
    gsub(/,Saintonge$/, "", eventlocal[event","id])
    gsub(/,Guyonne$/, "", eventlocal[event","id])
    gsub(/,Perche$/, "", eventlocal[event","id])
    gsub(/,Bourgogne$/, "", eventlocal[event","id])
    gsub(/,Bretagne$/, "", eventlocal[event","id])
    gsub(/,Presmontbarson$/, "", eventlocal[event","id])
    gsub(/,Champagne$/, "", eventlocal[event","id])
    gsub(/,Dauphine$/, "", eventlocal[event","id])
    gsub(/,Aunis$/, "", eventlocal[event","id])
    gsub(/,Chartres$/, "", eventlocal[event","id])
    gsub(/,Chartes$/, "", eventlocal[event","id])
    gsub(/,Guyere$/, "", eventlocal[event","id])
    gsub(/,Chartres Orleann$/, "", eventlocal[event","id])
    gsub(/,Ile-de-France$/, "", eventlocal[event","id])
    gsub(/,Langres$/, "", eventlocal[event","id])
    gsub(/,Aujou$/, "", eventlocal[event","id])
    gsub(/,Anjou$/, "", eventlocal[event","id])
    gsub(/,Poitou-Charentes$/, "", eventlocal[event","id])
    gsub(/,Dorset$/, "", eventlocal[event","id])
    gsub(/,Devon$/, "", eventlocal[event","id])
    gsub(/,Mortagne$/, "", eventlocal[event","id])
    gsub(/,Gruyere$/, "", eventlocal[event","id])
    gsub(/,Jura$/, "", eventlocal[event","id])
    gsub(/,Touraine$/, "", eventlocal[event","id])
    gsub(/,Toulouse$/, "", eventlocal[event","id])
    gsub(/,Sens$/, "", eventlocal[event","id])
    gsub(/,Ev\. Sees$/, "", eventlocal[event","id])
    gsub(/,Loire-Atlantique$/, "", eventlocal[event","id])
    gsub(/,Larochelle$/, "", eventlocal[event","id])
    gsub(/,Warwicks$/, "", eventlocal[event","id])
    gsub(/,Worchestershire$/, "", eventlocal[event","id])
    gsub(/,Pays Douche$/, "", eventlocal[event","id])
    gsub(/,Hertfordshire$/, "", eventlocal[event","id])
    gsub(/,Namur$/, "", eventlocal[event","id])
    gsub(/,Bohemia$/, "", eventlocal[event","id])
    gsub(/,Nordrhein-Westfalen$/, "", eventlocal[event","id])


    # Some places have a different name now
    gsub(/Beaubassin/, "Amherst", eventlocal[event","id])
}

function printInfo(id)
{
    cleanlocality(id, "BIRT")

    if (humanReadable == 1)
    {
	print "-----" 
	print "Name: " name[id]
	print "Born: " byear(id)
	print "Birthplace: " bplace(id)
	print "Died: " dyear(id)
	print "Death place: " dplace(id)
    }
    else if (listOfBirthplaces == 1)
    {
	if (!headerPrinted)
	{
	    print "Name;Locality;State"
	    headerPrinted = 1
	}
	if (length(bplace(id))>0)
	    print standardASCII(name[id]) ";" blocal(id) ";" btrack(id)
    }
    else
	print name[id]"|"byear(id)"|"bplace(id)"|"dyear(id)"|"dplace(id)
}
#
# We will say that a person was alive in a given year if their birth date
# and death date indicate that they were alive in any part of that year,
# or if they are missing a death date and would have been less than some
# given number of years old.
#
function aliveIn(id, year)
{
    if (((length(byear(id)) > 0) && (length(dyear(id)) > 0) &&
	(byear(id) <= year) && (dyear(id) >= year)) ||
	((length(byear(id)) > 0) && (length(dyear(id)) == 0) &&
	 (byear(id) <= year) && (byear(id) + 80 >= year)))
	return 1
    else
	return 0
}

function bornIn(id, yearStart, yearEnd)
{
    if (length(byear(id) > 0) && 
	(byear(id) >= yearStart) && (byear(id) <= yearEnd))
	return 1
    else
	return 0
}

function printAlive(id, year)
{
    if (length(id) == 0)
	return

    if (aliveIn(id, year))
	printInfo(id)
    printAlive(husband[famc[id]], year)
    printAlive(wife[famc[id]], year)
}

function printBorn(id, yearStart, yearEnd)
{
    if (length(id) == 0)
	return

    if (bornIn(id, yearStart, yearEnd))
	printInfo(id)
    printBorn(husband[famc[id]], yearStart, yearEnd)
    printBorn(wife[famc[id]], yearStart, yearEnd)
}

function birthorder(id,   i, j, rv)
{
    rv = 1
    for (i = 1; i <= numberOfFams[husband[famc[id]]]; i++)
	for (j = 1; j <= kids[fams[husband[famc[id]]","i]]; j++)
	    if (byear(child[fams[husband[famc[id]]","i]","j]) < byear(id))
		rv++
    for (i = 1; i <= numberOfFams[wife[famc[id]]]; i++)
	if (famc[id] != fams[wife[famc[id]]","i])
	    for (j = 1; j <= kids[fams[wife[famc[id]]","i]]; j++)
		if (byear(child[fams[wife[famc[id]]","i]","j]) < byear(id))
		    rv++
    return rv
}


function ageFirstChild(id,   i, j, earliestBirth, by)
{
    earliestBirth = 10000
    for (i = 1; i <= numberOfFams[id]; i++)
	for (j = 1; j <= kids[fams[id","i]]; j++)
	{
	    by = byear(child[fams[id","i]","j]) + 0
	    if ((by > 0) && (by < earliestBirth))
		earliestBirth = by
	}
    if ((byear(id) > 0) && (earliestBirth < 10000))
	return earliestBirth - byear(id)
    else
	return 0
}

function ageLastChild(id,    i, j, latestBirth, by)
{
    latestBirth = 0
    for (i = 1; i <= numberOfFams[id]; i++)
	for (j = 1; j <= kids[fams[id","i]]; j++)
	{
	    by = byear(child[fams[id","i]","j]) + 0
	    if (by > latestBirth)
		latestBirth = by
	}
    if (byear(id) > 0 && (latestBirth > 0))
	return latestBirth - byear(id)
    else
	return 0
}

function ageFirstMarriage(id,    i, earliestMarriage, md)
{
    earliestMarriage = 10000
    for (i = 1; i <= numberOfFams[id]; i++)
    {
	md = year(marrDate[fams[id","i]])
	if ((md > 0) && (md < earliestMarriage))
	    earliestMarriage = md
    }
    if (byear(id)>0 && (earliestMarriage < 10000))
	return earliestMarriage - byear(id)
    else
	return 0
}

function calculateAncestors(id)
{
    if (length(id) == 0)
	return
    if ((dyear(id) > 0) && (byear(id) > 0))
	ageAtDeath[id] = dyear(id) - byear(id)
    if ((byear(id) > 0) && (byear(wife[famc[id]]) > 0))
	agem[id] = byear(id) - byear(wife[famc[id]])
    if ((byear(id) > 0) && (byear(husband[famc[id]]) > 0))
	agef[id] = byear(id) - byear(husband[famc[id]])

    for (i = 1; i <= numberOfFams[husband[famc[id]]]; i++)
	if (famc[id] != fams[husband[famc[id]]","i])
	    halfsibs[id] += kids[fams[husband[famc[id]]","i]]
    for (i = 1; i <= numberOfFams[wife[famc[id]]]; i++)
	if (famc[id] != fams[wife[famc[id]]","i])
	    halfsibs[id] += kids[fams[wife[famc[id]]","i]]
    totalsibs[id] = halfsibs[id] + kids[famc[id]]
    calculateAncestors(husband[famc[id]])
    calculateAncestors(wife[famc[id]])
}

function findfirstmissing(level, id, inNA)
{
    if (level > levelsFirstMissing)
	levelsFirstMissing = level

    if ((bornCont(id) == "Europe") || (btrack(id) == NativeAmerica))
	return 0

    if (famc[id] ~ /@/)
    {
	if (husband[famc[id]] ~ /@/)
	    findfirstmissing(level+1,husband[famc[id]]);
	else
	    missing[level+1","++nmissing[level+1]] = "father of " name[id] " " btrack(id)

	if (wife[famc[id]] ~ /@/)
	    findfirstmissing(level+1,wife[famc[id]]);
	else
	    missing[level+1","++nmissing[level+1]] = "mother of " name[id] " " btrack(id)
    }
    else
    {
	missing[level+1","++nmissing[level+1]] = "parents of " name[id] " " btrack(id)
    }
}

function printmissing(l,   i)
{
    if (l <= levelsFirstMissing)
    {
	for (i = 1; i <= nmissing[l]; i++)
	    printf("Level %2d: %s\n",l,missing[l","i])
	printmissing(l+1)
    }
}


function drawKey(    a)
{
    printf("function drawKey() {\n");
    printf("ctx.font = '20px Verdana';\n");

    for (a=1; a<=trackingStates; a++)
    {
	printf("ctx.beginPath()\n");
	printf("ctx.arc(%d,%d,%d,0,tau);\n",x,y - keyRadius, keyRadius);
	printf("ctx.fillStyle = '%s';\n",colorOf[countryOfKeyOrder[a]]);
	printf("ctx.fill();\n");
	printf("ctx.strokeStyle = 'black';\n");
	printf("ctx.stroke();\n");
	printf("ctx.fillStyle = 'black';\n");
	printf("ctx.fillText(\"%s\",%d,%d);\n",countryOfKeyOrder[a],xText,y-2);
	y += 40
    }
    printf("}\n");
    printf("drawKey()\n");
}

BEGIN {
# default is to show through max level of 13
# for lines not known to be in Europe
    maxlevel = 2
    earliest_year = 1200
    latest_year = 2100

# initialize global variables
    id = "none"
    init()

# initialize display variables for graphical tree
    y = 460
    keyRadius = 10
    x = 10 * keyRadius + 40
    xText = x + 2 * keyRadius

    for (i=2; i<ARGC; i++)
    { 
	ZARGV[i]=ARGV[i]; 
	ARGV[i]=""
    }

}

# MAIN() PROCESSING LINE BY LINE
{
    indent = $1
    lineStart = ""

# The first field is a number that is equivalent to indentation.
# An indent of 0 indicates a new item.
    if (indent == 0)
    {
# Close out former item that we were working on
#	if (type[0] == "INDI")

# Set up new fields
	id = $2
	type[0] = $3
    }
    else
# we are continuing to process within a Level 0 type
    {
	type[indent] = $2
	if (type[0] == "INDI")
	{
	    if ((indent == 1) && (type[1] == "NAME")&&(length(name[id]) == 0))
	    {
		name[id] = substr($0, 8, length($0) - 8)
		gsub(/\//, "", name[id])
	    }
	    if ((indent == 1) && (type[1] == "SEX")&&
		((length(sex[id])==0) || (sex[id] == "U")))
		sex[id] = substr($0, 7, 1)
	    if ((indent == 1) && (type[1] == "FAMC")&&(length(famc[id]==0)))
		famc[id] = substr($0, 8, length($0) - 8)
	    if ((indent == 2) && (type[1] == "EVEN") && (type[2] == "TYPE"))
	    {
	        type_of_type = $3
		gsub(/\r/, "", type_of_type)
	    }
	    if ((indent == 2) && (type[1] == "EVEN") && 
		(type_of_type == "Arrival") && (type[2] == "DATE") &&
		(length(arrival[id])==0))
	    {
		arrival[id] = substr($0, 8, length($0) - 8)
	    }

	    if ((indent == 2) && ((type[1] == "BIRT") || 
				  (type[1] == "DEAT")) &&
		(type[2] == "DATE") && (length(eventdate[type[1]","id])==0))
	    {
		idx = type[1] "," id
		eventdate[idx] = substr($0, 8, length($0) - 8)
		eventyear[idx] = year(eventdate[idx])
		if (eventyear[idx] == 0)
		{
		    print "----"
		    print "Problem: " type[1] " year id " id " name=" name[id]
		    print eventyear[idx] " | " eventdate[idx]
		    print "----"
		}
	    }
	    if ((indent == 2) && 
		((type[1] == "BIRT") || (type[1] == "DEAT")) &&
		(type[2] == "PLAC") &&
		(length(eventplace[type[1]","id] == 0)))
	    {
		idx = type[1] "," id
		eventplace[idx] = substr($0, 8, length($0) - 8)
#
# How to find the canonical name for the birth/death place and ensure that
# we have a birth state, country, and continent.
# If it is stored in the canonical format, it would look like
# Town, County, State, Country
# But the state or the country might be missing
# It might be an abbreviation or alternate name for the state or country
# They might use periods to separate the items, or just spaces
# They might use varying capitalization, or have extra notes in parentheses
# We could require the data be cleaned, but it's convenient to be as generous
# as possible in interpreting the places.
# So, steps
# - remove anything in parentheses
# - Try splitting based on a comma, clean up the last item, and check
# - If that doesn't work, try splitting based on periods
# - If that doesn't work, try splitting based on spaces
#    - If one space doesn't work, try combining the final two
#
# "Cleaning up an item"
# - remove any leading and trailing spaces and punctuation
# - uppercase it and canonicalize it
#
# Other things we could possibly add to improve this
# 1. Include a way to add the known state/country for a given city
# 2. See if the item inside the parentheses works
# 3. Deal more gracefully with it if no place is found

		# Remove anything in parentheses
		gsub(/\([-A-Za-z0-9.,éô' ]*\)/,"",eventplace[idx])

		# Remove leading and trailing spaces, commas, periods
		gsub(/^[ ,\.]+/,"",eventplace[idx])
		gsub(/[ ,\.]+$/,"",eventplace[idx])

		splitters[0] = ","
		splitters[1] = "."
		splitters[2] = " "
		for (j = 0; j <= 2; j++)
		{
		    numpl = split(eventplace[idx], places, splitters[j])

		    # For each internal section
		    for (i = 0; i <= numpl; i++)
		    {
			# Remove leading and trailing spaces, commas, periods
			gsub(/^[ ,\.]+/,"",places[i])
			gsub(/[ ,\.]+$/,"",places[i])
		    }
		    
		    # if there is a more standard version of the name, use that
		    if (length(canonical[toupper(places[numpl])]) > 0)
			places[numpl] = canonical[toupper(places[numpl])]
		    if (length(canonical[toupper(places[numpl-1])]) > 0)
			places[numpl-1] = canonical[toupper(places[numpl-1])]

		    if (isCountry(places[numpl]) || isNAState(places[numpl]))
			break
		}

		if (!isCountry(places[numpl]) && !isNAState(places[numpl]))
		{
		    # try combining the last 2 items (e.g., "Albany New York")
		    places[numpl-1] = places[numpl-1] " " places[numpl]
		    if (length(canonical[toupper(places[numpl-1])]) > 0)
		    {
			numpl--
			places[numpl] = canonical[toupper(places[numpl])]
			if (length(canonical[toupper(places[numpl-1])]) > 0)
			    places[numpl-1] = canonical[toupper(places[numpl-1])]
		    }
		}

		# check to see if we have a country or state at the end
		if (!isCountry(places[numpl]) &&  !isNAState(places[numpl]))
		    print "No " type[1] " st/country " id " | " eventplace[idx]

		if (isCountry(places[numpl]))
		{
		    eventcountry[idx] = places[numpl--]
		    eventcontinent[idx] = continentOf(eventcountry[idx])
		}
		if (isNAState(places[numpl]))
		{
		    if (eventcountry[idx] != NativeAmerica)
		    {
			if (isCanadianProvince(places[numpl]))
			    eventcountry[idx] = "Canada"
			else
			    eventcountry[idx] = "US"
		    }
		    eventstate[idx] = places[numpl]
		    eventcontinent[idx] = "North America"
		    numpl--
		}
		eventlocal[idx] = places[numpl--]
		while (numpl > 0)
		    eventlocal[idx] = places[numpl--] "," eventlocal[idx]

		if ((eventcontinent[idx] == "North America") &&
		    (eventcountry[idx] != NativeAmerica))
		    eventtrack[idx] = eventstate[idx]
		else
		    eventtrack[idx] = eventcountry[idx]
	    }
	}
	else if (type[0] == "FAM")
	{
	    if ((indent == 1) && (type[1] == "HUSB") && length(husband[id]==0))
	    {
		husband[id] = substr($0, 8, length($0) - 8)
		numberOfFams[husband[id]]++
		fams[husband[id]","numberOfFams[husband[id]]] = id
	    }
	    if ((indent == 1) && (type[1] == "WIFE") && length(wife[id] == 0))
	    {
		wife[id] = substr($0, 8, length($0) - 8)
		numberOfFams[wife[id]]++
		fams[wife[id]","numberOfFams[wife[id]]] = id
	    }

	    if ((indent == 2) && (type[1] == "MARR") && (type[2] == "DATE"))
	    {
		marrDate[id] = substr($0, 8, length($0) - 8)
	    }
	    if ((indent == 1) && (type[1] == "CHIL"))
	    {
		kids[id]++
		child[id","kids[id]] = substr($0, 8, length($0) - 8)
	    }
	}
    }
}

# Now that we've read in all the data, we want to print out something about it.
# We may need to take some action first, something that couldn't be done
# until all the data was present, like tracking down ancestral branches.

END{
# s is the starting person

# Romain
#    s = "@P5775@"

# Bart
    s = "@P1@"

    markString = "Bart"
    markAncestors(s, markString, 1)
    calculateAncestors(s)
    cousinDegree = 2
# includeMissing
    im = 0

# Command will look like:
# ged file       - equivalent to "ged file Normal"
# ged file Color
# ged file Missing
# ged file IDs
# ged file Alive year [Human | Birthplace]
# ged file Born year1 year2 [Human | Birthplace]
# ged file Dump

    if (ARGC > 2)
	printType = ZARGV[2]
    else 
	printType = "Normal"

#function printfam(currentLevel, maxLevel, pathSoFar, currentID, ancestralBirth, ancestorName, includeMissing, printType)
#    printType: America, Canada, Immigrant, Normal, Color, Missing, IDs

# Could add the ability to choose a few options
# who to start with, whether to mark common ancestors, max depth

#    markAncestors("@P1@","CanAnc", 0)

    if (printType == "Color")
    {
	depth = 12
	drawKey()
	printf("var depth = %d;\n", depth+1);
	printfam(0, depth, "", s, "", "", 1, "Color", "")
    }

    else if (printType == "Missing")
    {
	findfirstmissing(0, s)
	printmissing(0)
    }

    else if (printType == "IDs")
	printfam(0, 15, "", s, "", "", 0, "IDs", "")

    else if (printType == "Alive")
    {
	if (ZARGV[4] == "Human")
	    humanReadable = 1
	else if (ZARGV[4] == "Birthplace")
	    listOfBirthplaces = 1
	printAlive(s, ZARGV[3])
    }
    else if (printType == "Born")
    {
	if (ZARGV[5] == "Human")
	    humanReadable = 1
	else if (ZARGV[5] == "Birthplace")
	    listOfBirthplaces = 1
	printBorn(s, ZARGV[3], ZARGV[4])
    }
    else if (printType == "Dump")
    {
	printfamheader()
	printfam(0, 14, "", s, btrack(s), name[s], im, printType, "")
#	printfams(famc[s])
    }
    else if (printType == "DumpPlus")
    {
	dumpTreePlusChildren(s)
    }
    else
    {
	printfam(0, 14, "", s, btrack(s), name[s], im, printType, "")
#	findCousins(s, cousinDegree)

    }
}

