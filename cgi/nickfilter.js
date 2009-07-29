/*
Maybe-helpful filtering-by-nick stuff. Lets you filter nicks in/out, thus
letting you view particular conversations. Sorta.

/msg missingthepoint or bpetering in #perl6 with bug complaints :)
*/

// Settings

// match _id vars in style.css
var filterbox_id            = 'filterbox';
var filter_toggle_id        = 'filter_toggle';    // match in HTML

var filter_hidden_id        = 'filter_hidden';
var filter_shown_id         = 'filter_shown';

var nick_id_prefix          = 'fn_nick_';

// match in CSS
var tbl_id                  = 'log';
var expanded_tbl_width      = '100%';
var shrunk_tbl_width        = '65%';

// Globals

var all_nicks = new Object();
var hidden_nicks = new Object();
var shown_nicks = new Object();
var nick_regex_str = '';
var tbl_width = '';

$(document).ready(function() {
    
    try {
        process_html();
    } catch(e) { alert(e) }
    
    /** Create filter panel/box thingy and add nicks */
    try {
        var filterbox = document.createElement("div");
        $(filterbox).hide().css("position", "fixed"); /* don't move onscroll */
        $(filterbox).attr("id", filterbox_id);
    
        // Add to body element
        $("body").append(filterbox);        
        
        $(filterbox).append(
            '<h2>Conversation</h2>'

            + '<p id="show_hide_all">'
            + ' <a href="javascript:show_all()">Show All</a>'
            + ' <a href="javascript:hide_all()">Hide All</a>'
            + '</p>'

            + '<div id="shown_nicks">'
            + '<h3>Shown nicks</h3>'            
            + '<div id="' + filter_shown_id + '" class="nick_list">'
            + '</div></div>'
            
            + '<div id="hidden_nicks">'
            + '<h3>Hidden nicks</h3>'            
            + '<div id="' + filter_hidden_id + '" class="nick_list">'
            + '</div></div>'
            
            + '<p id="filtering_off">'
            +  '<a href="javascript:filtering_off()">Filtering Off</a>'
            + '</p>'
        );
    } catch(e) { alert(e) }

    $("#"+filter_toggle_id).append(
        '<a href="javascript:filtering_on()">Turn on filtering by nick</a>'
    );
    $("#"+filter_toggle_id).show();
    
});


function obj_props(obj) {
    var ret_array = new Array();
    for (var i in obj) {
        ret_array.push(i);
    }
    return ret_array;
}

// Convert an Array of strings to a string with regex matching any of them
// Doesn't handle metachars or anchoring at all.
function array_to_regex_str(array) {
    var regex_str = '';
    for (var i = 0; i < array.length; i++) {
        if (i > 0) {
            regex_str += '|';
        }
        regex_str += array[i];
    }
    return regex_str;
}

/** Pull nicks from HTML, put in initial store objects, build regex
    to match any nick on page */
function process_html() {
    $("tr.nick").each(function() {
        var this_class  = $(this).attr("class");
        var extr_re     = new RegExp("nick_([^\x20]+)");
        var matches     = this_class.match(extr_re);
        
        if (matches) {
            all_nicks[ matches[1] ] = 1;
            hidden_nicks[ matches[1] ] = 1;
        }
    });
    nick_regex_str = array_to_regex_str(obj_props(all_nicks));    
}

function render_nicklists() {
    var hidden_list = obj_props(hidden_nicks);
    var shown_list = obj_props(shown_nicks);
    
    $("#"+filter_hidden_id).empty();    // not .html('') -> crashes stuff
    $("#"+filter_shown_id).empty();
    
    hidden_list.sort();
    for (var i=0; i < hidden_list.length; i++) {
        $("#"+filter_hidden_id).append(gen_nick_html(hidden_list[i]));
    }
    
    shown_list.sort();
    for (var i=0; i < shown_list.length; i++) {
        $("#"+filter_shown_id).append(gen_nick_html(shown_list[i]));
    }      
}

/** For a given nick, generate the HTML for the filter box */
function gen_nick_html(nick) {
return  '<div id="' + nick_id_prefix + nick + '" class="row">'
    + '<span class="nick"><a href="javascript:toggle_nick(\'' +nick+ '\')">'
        + nick + '</a></span>'
    + '<span class="spoken_to">(Spoken to: </span>'
    + '<span class="spoken_to_show"><a href="javascript:show_spoken_to(\''
        + nick + '\')">show</a></span>'
    + '<span class="spoken_to_hide"><a href="javascript:hide_spoken_to(\''
        + nick + '\')">hide</a>)</span>'    
    + '</div>'
;
}

// Switch a single nick between categories (shown/hidden)
function toggle_nick(nick) {
    if (hidden_nicks[nick]) {        
        show_nick(nick);
    }
    else if (shown_nicks[nick]) {        
        hide_nick(nick);
    }
    else {
        alert('BUG; impossible');
    }
    filtering_apply();
    render_nicklists();
}

// Add a single nick
function show_nick(nick) {
    delete hidden_nicks[nick];      // can't be in both at once
    shown_nicks[nick] = 1;    
}

// Remove a single nick
function hide_nick(nick) {
    delete shown_nicks[nick];       // can't be in both at once
    hidden_nicks[nick] = 1;
}

// Add all nicks a given nick spoke to ("$nick: ..." or "$nick, ...")
// to/from conversation
function show_spoken_to(nick) {  
    $("tr.nick_" + nick + " td.msg").each(function() {
        var msg = $(this).html();

        // TODO what if NRS matched multiple nicks?
        var matches = msg.match(new RegExp('(' + nick_regex_str + ')[:,]'));
        if (matches) {
            var nick = matches[1];
            show_nick(nick);
        }
    });
    filtering_apply();
    render_nicklists();
}

// Remove all nicks a given nick spoke to ("$nick: ..." or "$nick, ...")
// to/from conversation
function hide_spoken_to(nick) {  
    $("tr.nick_" + nick + " td.msg").each(function() {
        var msg = $(this).html();

        // TODO what if NRS matched multiple nicks?
        var matches = msg.match(new RegExp('(' + nick_regex_str + ')[:,]'));
        if (matches) {
            var nick = matches[1];
            hide_nick(nick);
        }
    });
    filtering_apply();
    render_nicklists();    
}

// These two: Empty one object and move nicks to other

function show_all() {
    var hidden_list = obj_props(hidden_nicks);
    for (var i = 0; i < hidden_list.length; i++) {
        show_nick( hidden_list[i] );
    }
    filtering_apply();
    render_nicklists();    
}
function hide_all() {
    var shown_list = obj_props(shown_nicks);
    for (var i = 0; i < shown_list.length; i++) {
        hide_nick( shown_list[i] );
    }
    filtering_apply();
    render_nicklists();    
}


// These apply/unapply filtering for ALL nicks
function filtering_apply() {
    var show_list = obj_props(shown_nicks);
    $("tr").hide();
    for (var i = 0; i < show_list.length; i++) {
        $("tr.nick_"+show_list[i]).show();
    }
}
function filtering_unapply() {
    $("tr").show();
}

function shrink_table() {
    $("#"+tbl_id).css("width", shrunk_tbl_width);
}

function expand_table() {
    $("#"+tbl_id).css("width", expanded_tbl_width);
}

function filtering_on() {
    $("#" +filter_toggle_id+ ">a").html("Turn off filtering by nick");
    $("#" +filter_toggle_id+ ">a").attr("href", 'javascript:filtering_off()');
    
    shrink_table();
    $("#"+filterbox_id).fadeIn();
    
    filtering_apply();
    render_nicklists();
}

function filtering_off() {
    // Could do a reset here by removing all properties from
    // hidden_nicks / shown_nicks, but I think it's a feature we don't -
    // can then switch between "full" view and the filtered conversation
    // we set up.
    
    filtering_unapply();
    $("#"+filterbox_id).fadeOut();
    expand_table();

    $("#" + filter_toggle_id + ">a").html("Turn on filtering by nick");
    $("#" + filter_toggle_id + ">a").attr("href", 'javascript:filtering_on()');
}
