/* Maybe-helpful filtering-by-nick stuff. */

// Settings

// match _id vars in style.css
var filterbox_id          = 'filterbox';
var filter_toggle_id      = 'filter_toggle';    // match in HTML

var filter_hidden_id      = 'filter_hidden';
var filter_shown_id       = 'filter_shown';

var normalnick_id_prefix  = 'fn_nick_';

var special_metanick_id   = 'fn_specialnick';
var special_metanick_text = '(SPECIAL)';
var special_metanick_nick = 'special';

// Globals

var hidden_nicks = new Object();
var shown_nicks = new Object();
var show_special = false;          // bool

// Set up nick filtering stuff when DOM is ready, i.e. when
//  we have all message rows ready to process
$(document).ready(function() {
    var i = 0;
    var ac_nicks = new Array();
    var nicks_seen = new Object();
    var nick;
    
    /** Pull nicks from HTML, put in initial store obj */
    try {
        $("tr.nick").each(function() {
            var this_class  = $(this).attr("class");
            var extr_re     = new RegExp("nick_([^\x20]+)");
            var matches     = this_class.match(extr_re);
            if (matches) {
                var nick        = matches[1];
                //if (i++ < 5) { alert(nick); }
                hidden_nicks[ nick ] = 1;
            }
        });
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
            + '<p>"' + special_metanick_text + '" == quits/joins etc</p>'            

            + '<div id="hidden_nicks">'
            + '<h3>Add nicks</h3>'            
            + '<ul id="' + filter_hidden_id + '">'
            + '</ul>'
            
            + '<div id="shown_nicks">'
            + '<h3>Remove nicks</h3>'            
            + '<ul id="' + filter_shown_id + '">'
            + '</ul>'
            
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

// not going to bother refactoring further ATM
function render_nicklists() {
    var hidden_list = obj_props(hidden_nicks);
    var shown_list = obj_props(shown_nicks);
    
    $("#"+filter_hidden_id).html('');
    $("#"+filter_shown_id).html('');
    
    hidden_list.sort();
    for (var i=0; i < hidden_list.length; i++) {
        $("#"+filter_hidden_id).append(gen_fnli_html(hidden_list[i]));
    }
    
    shown_list.sort();
    for (var i=0; i < shown_list.length; i++) {
        $("#"+filter_shown_id).append(gen_fnli_html(shown_list[i]));
    }      
}

function gen_fnli_html(nick) {
    if (nick == special_metanick_nick) {
        return  '<li id="' + special_metanick_id + '">'
                + '<a href="javascript:toggle_nick(\''
                + special_metanick_nick + '\')">'
                + special_metanick_text
                + '</a></li>'    
        ;        
    }
    else {
        return  '<li id="' + normalnick_id_prefix + nick + '">'
                + '<a href="javascript:toggle_nick(\'' + nick + '\')">'
                + nick
                + '</a>'
                + ' (&rarr; <a href="javascript:add_spoken_to(\''
                + nick
                + '\')">spoken to</a>)'                
                + '</li>'
        ;
    }
}

function toggle_nick(nick) {
    if (hidden_nicks[nick]) {        
        delete hidden_nicks[nick];
        shown_nicks[nick] = 1;
    }
    else {        
        delete shown_nicks[nick];
        hidden_nicks[nick] = 1;
    }
    filtering_apply();
    render_nicklists();
}

// Adds all nicks a given nick spoke to ("$nick:") to conversation
function add_spoken_to(nick) {
    var i = 0;
    alert('adding ST (nick='+nick+')...');
    $("tr.nick_" + nick + " td.msg").each(function() {
        var msg = $(this).html();
        var matches = msg.match(/([^:]+):/);
        if (matches) {
            var nick = matches[1];
            
            // If we can't find them in in hidden Obj, do nothing. Might not
            // be present on page.
            if (hidden_nicks[nick]) {
                toggle_nick(nick);
            }
        }
    });
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

function filtering_on() {
    $("#" + filter_toggle_id + " > a").html("Turn off filtering by nick");
    $("#" + filter_toggle_id + " > a").attr("href", 'javascript:filtering_off()');
    $("#"+filterbox_id).fadeIn();
    filtering_apply();
    render_nicklists();
}

function filtering_off() {
    filtering_unapply();
    $("#"+filterbox_id).fadeOut();    
    $("#" + filter_toggle_id + " > a").html("Turn on filtering by nick");
    $("#" + filter_toggle_id + " > a").attr("href", 'javascript:filtering_on()');
}
