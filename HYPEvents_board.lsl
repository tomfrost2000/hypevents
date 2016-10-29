//
// HYPEvents in-world teleporter board script
// Version: 0.8
// Author: Tom Frost <tomfrost@linkwater.org>
// Additions: Gudule Lapointe <gudule@speculoos.world>
//  - theme setttings are taken in account
//  - font name and size configurable in setttings
//  - separate font name and size for hour display
//  - fixed column width based on hour font size.
//
// GPLv3
//

// configuration:

// if set to TRUE, show all events
// if set to FALSE, only show events that started at most 2 hours ago
integer showAll = FALSE;

// if set to TRUE, warn owner when new version is available
integer warnVersion = TRUE;

// time (in seconds) between refreshing
float refreshTime = 1800;

// a theme (see 'theme definitions' for options)
string theme = "red";
 
// theme definitions
// a definition is a list of name, background color foreground color, header image url
list themes = [
    "standard", "ffffffff", "ff000000", "http://linkwater.org/dyntex/hypevents_logo.png",
    "terminal", "ff000000", "ff00ff00", "http://linkwater.org/dyntex/hypevents_logo_terminal.png",
    "red", "ffff0000", "ffffff00", "http://linkwater.org/dyntex/hypevents_logo_red.png"
    ];

// font name and size for event descriptions
string fontName = "Arial";
integer fontSize=20;

// font name and size for time display
string hourFontName = "Arial";
integer hourFontSize = 16;

// internal, do not touch:
integer lineHeight = 30;
integer startY = 90;

integer texWidth = 512;
integer texHeight = 512;
key httpRequest;

list events;

list eventIndices;

integer channel;

integer listenHandle;
integer listening = 0;

list avatarDestinations = [];

string scriptVersion = "0.8";

// return -1 if s1 is lexicographically before s2,
//         1 if s2 is lexicographically before s1,
//         0 if s1 is equal to s2
// adaped from http://wiki.secondlife.com/wiki/String_Compare
integer tfStrcmp(string s1, string s2)
{
    if (s1 == s2)
        return 0;
 
    if (s1 == llList2String(llListSort([s1, s2], 1, TRUE), 0))
        return -1;
 
    return 1;
}

//
// manipulate global avatarDestinations list
//
// insert or overwrite destination for agent with dest
//
tfSetAvatarDest(key agent, string dest)
{
    list newList = [];
    integer idx;
    integer len = llGetListLength(avatarDestinations)/2;
    integer set = FALSE;

    for(idx=0;idx<len;idx++) {
        key avatar = llList2Key(avatarDestinations, (idx*2));
        if(avatar==agent) {
            newList += [ agent, dest ];
            set = TRUE;
        } else {
            newList += [ avatar, llList2String(avatarDestinations, (idx*2)+1) ];
        }
    }
    if(!set) {
        newList += [ agent, dest ];
    }

    avatarDestinations = newList;
}

//
// retrieve avatar dest from global avatarDestination list
//
// returns hgurl if destination set, NULL_KEY otherwise
//
string tfGetAvatarDest(key agent)
{
    integer idx;
    integer len = llGetListLength(avatarDestinations)/2;

    for(idx=0;idx<len;idx++) {
        if(llList2Key(avatarDestinations, (idx*2))==agent) {
            return llList2String(avatarDestinations, (idx*2)+1);
        }
    }
    return NULL_KEY;
}

doRequest()
{
    httpRequest = llHTTPRequest("http://hypevents.net/events.lsl2", 
                                [HTTP_BODY_MAXLENGTH, 4096], 
                                "");
}

string tfTrimText(string in, string fontname, integer fontsize,integer width)
{
    integer i;
    integer trimmed = FALSE;

    for(;llStringLength(in)>0;in=llGetSubString(in,0,-2)) {

        vector extents = osGetDrawStringSize("vector",in,fontname,fontsize);

        if(extents.x<=width) {
            if(trimmed) {
                return in + "…";
            } else {
                return in;
            }
        }

        trimmed = TRUE;
    }

    return "";
}

refreshTexture()
{
    string commandList = "";
    
    eventIndices = [];

    integer themeIdx = llListFindList(themes, theme);
    string backgroundColor = llList2String(themes, themeIdx + 1);
    string fontColor = llList2String(themes, themeIdx + 2);
    string logo = llList2String(themes, themeIdx + 3);

    commandList = osSetPenColor(commandList, fontColor);
    commandList = osMovePen(commandList, 20, 5);
    commandList = osDrawImage(commandList, 400, 70, logo);

    commandList = osSetPenSize(commandList, 1);
    commandList = osDrawLine(commandList, 0, 80, 512, 80);

    integer numEvents = llGetListLength(events)/3;

    integer i;

    integer y = startY;

    integer secondMargin = 10 + hourFontSize * 6;
    // rough estimation, but it works quite well

    integer notBefore = llGetUnixTime() - (2*3600);
    
    integer numEventsShown = 0;
    
    for(i=0;i<numEvents && numEventsShown<14;i++) {
        integer base = i*3;
        
        // this is a ~-seperated list of time specifiers
        // it has 6 fields, but may be extended with more fields in the
        // future
        // fields are start-time~start-date~start-timestamp~end-time~end-date~end-timestamp
        // timestamps are seconds since the unix epoch (January 1st 1970, 00:00 UTC)
        string timeSpecifier = llList2String(events, base+1);
        list timeParsed = llParseString2List(timeSpecifier, ["~"], []);

        
        if(showAll || llList2Integer(timeParsed, 2) > notBefore) {
            eventIndices += i;
            
            commandList = osMovePen(commandList, 10, y + fontSize - hourFontSize);
            commandList = osSetFontName(commandList, hourFontName);
            commandList = osSetFontSize(commandList, hourFontSize);
            commandList = osDrawText(commandList, llList2String(timeParsed, 0));
    
            string text = llList2String(events, base);
            text = tfTrimText(text, fontName, fontSize, texWidth-30-secondMargin);
            commandList = osMovePen(commandList, secondMargin, y);
            commandList = osSetFontName(commandList, fontName);
            commandList = osSetFontSize(commandList, fontSize);
            commandList = osDrawText(commandList, text);
    
            y += lineHeight;
            
            numEventsShown++;
        }
    }

    osSetDynamicTextureData("", "vector", commandList, "width:"+(string)texWidth+",height:"+(string)texHeight + ",bgcolor:" + backgroundColor, 0);
}

tfLoadURL(key avatar)
{
    llLoadURL(avatar, "Visit the HYPEvents web-site for more detailed event information and technical information.", "http://hypevents.net/");
}

// present dialog to avatar with hg / local choice, store destination
// keyed by avatar to retrieve when choice is made
tfGoToEvent(key avatar, integer eventIndex)
{
    integer numEvents = llGetListLength(events)/3;

    integer base = eventIndex * 3;

    if(eventIndex<numEvents) {
        string text=llList2String(events, base+0);

        text += "\n\n";

        text += "The hypergrid url for this event is:\n\n"+llList2String(events, base+2)+"\n\n";

        text += "Is this hgurl a hypergrid url for you or a local url?\n\n";

        tfSetAvatarDest(avatar, llList2String(events, base+2));

        llDialog(avatar, text, ["Hypergrid","Local grid", "Cancel"], channel);
        if(listening==0) {
            listenHandle = llListen(channel, "", NULL_KEY, "");
            listening = (integer)llGetTime();
        }
    } else {
    }
}

default
{
    state_entry()
    {
        channel = -25673 - (integer)llFrand(1000000);
        listening = 0;
        avatarDestinations = [];
        llSetTimerEvent(refreshTime);
        doRequest();
    }

    http_response(key requestID, integer status, list metadata, string body)
    {
        if(status==200) {
            events = llParseString2List(body, ["\n"], []);
            
            string version = llList2String(events, 0);
            events = llDeleteSubList(events, 0, 0);
            
            if(warnVersion && tfStrcmp(version, scriptVersion)!=0) {
                llOwnerSay("You are running version " + scriptVersion + " but a newer version (" + version + ") is available.");
                llOwnerSay("Head over to hypergrid.org:8002:Linkwater_South to get the latest version at the HYPEvents office.");
            }
            
            refreshTexture();
        } else {
            llOwnerSay("Unable to fetch event.lsl2, status: "+(string)status);
        }
    }

    listen(integer chan, string name, key agent, string msg)
    {
        if(chan==channel) {
            if(msg!="Cancel") {
                string dest = tfGetAvatarDest(agent);
                if(dest!=NULL_KEY) {
                    string dsturl = dest;
                    if(msg=="Local grid") {
                        list hgurl = llParseString2List(dest, [":"], []);
                        dsturl = llList2String(hgurl, 2);
                    }
                    osTeleportAgent(agent, dsturl, <128.0,128.0,23.0>, <1.0,1.0,0.0> );
                }
            }
        }
    }

    touch_end(integer num)
    {
        integer i;
        for(i=0;i<num;i++) {
            vector touchPos = llDetectedTouchUV(i);
            integer touchX = (integer)(touchPos.x * texWidth);
            integer touchY = texHeight - (integer)(touchPos.y * texHeight);
            key avatar = llDetectedKey(i);

            if(touchY < 80) {
                tfLoadURL(avatar);
            } else if(touchY>=startY) {
                integer touchIndex;
                integer eventIndex;

                touchIndex = (integer)((touchY - startY) / lineHeight);
                
                if(touchIndex < llGetListLength(eventIndices)) {
                    eventIndex = llList2Integer(eventIndices, touchIndex);
                    tfGoToEvent(avatar, eventIndex);
                }
            }
        }
    }

    timer()
    {
            // timeout listener
        if(listening!=0) {
            if( (listening + 300) < (integer)llGetTime() ) {
                llListenRemove(listenHandle);
                avatarDestinations=[];
                listening = 0;
            }
        }
            // refresh texture
        doRequest();
    }

    on_rez(integer start_param)
    {
        llResetScript();
    }

    changed(integer change)
    {
        if(change & CHANGED_SHAPE ||
           change & CHANGED_SCALE ||
           change & CHANGED_OWNER ||
           change & CHANGED_REGION
           ) {
               llResetScript();
        }
    }
}
