/*
Maybe-helpful filtering-by-nick stuff. Lets you filter nicks in/out, thus
letting you view particular conversations. Sorta.
*/

// Settings

// match _id vars in style.css
var filterbox_id            = 'filterbox';
var filter_toggle_id        = 'filter_toggle';    // match in HTML

var filter_hidden_ul_id     = 'filter_hidden';
var filter_shown_ul_id      = 'filter_shown';

var nick_id_prefix          = 'fn_nick_';

// match in CSS
var tbl_id                  = 'log';
var expanded_tbl_width     = '100%';
var shrunk_tbl_width        = '60%';

// Globals

var all_nicks = new Object();
var hidden_nicks = new Object();
var shown_nicks = new Object();
var nick_regex_str = '';
var tbl_width = '';

// Set up nick filtering stuff when DOM is ready, i.e. when
//  we have all message rows ready to process
$(document).ready(function() {
    
    /** Pull nicks from HTML, put in initial store obj */
    try {
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
        alert('set NRS='+nick_regex_str);
    } catch(e) { alert(e) }
    
    /** Create filter panel/box thingy and add nicks */
    try {
        var filterbox = document.createElement("div");
        $(filterbox).hide().css("position", "absolute");
        $(filterbox).attr("id", filterbox_id);
    
        // Add to body element
        $("body").append(filterbox);        
        
        $(filterbox).append(
            '<h2>Conversation</h2>'
            
            + '<div id="hidden_nicks">'
            + '<h3>Add nicks</h3>'            
            + '<ul id="' + filter_hidden_ul_id + '">'
            + '</ul></div>'
            
            + '<div id="shown_nicks">'
            + '<h3>Remove nicks</h3>'            
            + '<ul id="' + filter_shown_ul_id + '">'
            + '</ul></div>'
            
            + '<p><a href="javascript:filtering_off()">Filtering Off</a></p>'
        );
    } catch(e) { alert(e) }

    $("#"+filter_toggle_id).append('<a href="javascript:filtering_on()">Turn on filtering by nick</a>');
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

// not going to bother refactoring further ATM
function render_nicklists() {
    var hidden_list = obj_props(hidden_nicks);
    var shown_list = obj_props(shown_nicks);
    
    $("#"+filter_hidden_ul_id).empty();    // not .html('')    :)
    $("#"+filter_shown_ul_id).empty();
    
    hidden_list.sort();
    for (var i=0; i < hidden_list.length; i++) {
        $("#"+filter_hidden_ul_id).append(gen_fnli_html(hidden_list[i]));
    }
    
    shown_list.sort();
    for (var i=0; i < shown_list.length; i++) {
        $("#"+filter_shown_ul_id).append(gen_fnli_html(shown_list[i]));
    }      
}

function gen_fnli_html(nick) {
    return  '<li id="' + nick_id_prefix + nick + '">'
            + '<a href="javascript:toggle_nick(\'' + nick + '\')">'
            + nick
            + '</a>'
            + ' (Spoken to &rarr; '
            + '<a href="javascript:show_spoken_to(\''
            + nick
            + '\')">add</a>'
            + '&nbsp;|&nbsp;'
            + '<a href="javascript:hide_spoken_to(\''                
            + nick
            + '\')">remove</a>'    
            + ')'
            + '</li>'
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
    $("#" + filter_toggle_id + " > a").html("Turn off filtering by nick");
    $("#" + filter_toggle_id + " > a").attr("href", 'javascript:filtering_off()');
    
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

    $("#" + filter_toggle_id + " > a").html("Turn on filtering by nick");
    $("#" + filter_toggle_id + " > a").attr("href", 'javascript:filtering_on()');
}
