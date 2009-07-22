/* Enable filtering the current page to display only messages from a
   single nick, without context. Autocompletes all nicks on current page */
$(document).ready(function() {
    var i = 0;
    var ac_nicks = new Array();
    var nicks_seen = new Object();
    var nick;
    
    $("tr.nick").each(function() {
        var this_class  = $(this).attr('class');
        var extr_re     = new RegExp("nick_([^\x20]+)");
        var matches     = this_class.match(extr_re);
        var nick        = matches[1];
        //if (i++ < 5) { alert(nick); }
        ac_nicks.push(nick);
    });
    // uniq
    for (var i=0; i < ac_nicks.length; i++) {
        nicks_seen[ ac_nicks[i] ] = 1;   
    }
    ac_nicks.splice(0, ac_nicks.length); // empty
    for (nick in nicks_seen) {
        ac_nicks.push(nick);
    }
    ac_nicks.sort();
    
    $("#nick").autocomplete('', {}, ac_nicks);
});

function filter() {
    var nick = $("#nick").val();
    var jq_sel = "tr:not(.nick_" + nick + ")";
    $(jq_sel).hide();
}

function unfilter() {
    $("tr.nick").show();
}