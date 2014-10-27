function collapse($e) {
    var hash = window.location.hash;
    var uncollapse;

    $e.filter('.special.new').each(function (idx, elem) {
        var $elem = $(elem);
        var ids = [$elem.attr('id')];
        $elem.nextAll().each(function (i, e) {
            if ($(e).hasClass('special')) {
                $(e).addClass('hidden');
                if (hash && $(e).find(hash).length) {
                    uncollapse = ids[0];
                }
                ids.push($(e).attr('id'));
            }
            else {
                /* abort iteration */
                return false;
            }

        });
        var c = ids.length;
        if (c > 1) {
            $elem.data('ids', ids);
            $elem.addClass('hidden');
            var extra_class = 'light';
            if ($elem.hasClass('dark')) {
                extra_class = 'dark';
            }
            $elem.before('<tr class="special ' + extra_class + '"><td class="nick" /> <td /><td>' + c + ' more elements. <a href="javascript:show_collapsed(\'' + $elem.attr('id') + '\')">Show/hide.</a></td></tr>');
            if (uncollapse) {
                show_collapsed(uncollapse);
           }
        }
    });
}
// collapse mulitple joins/quits into one line
$(document).ready(function() {
    collapse($('table#log tr'))
    $('#notify').click(function() {
        $(this).hide().empty();
    });

    // the default scrolling doesn't work, because it happens before
    // collapse().
    var fragment = window.location.hash;
    if (fragment && fragment.length) {
        var elem = $(fragment)[0];
        if (elem) {
            elem.scrollIntoView();
        }
    }
});

function show_collapsed(id) {
    var ids = $('#' + id).data('ids');
    for (i in ids ) {
        $('#' + ids[i]).toggleClass('hidden');
    }
}
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
        $(filterbox).hide().css("position", "absolute");
        $(filterbox).attr("id", filterbox_id);

        // Add to body element
        $("body").append(filterbox);

        $(filterbox).append(
            '<h2>Conversation</h2>'

            + '<p id="show_hide_all">'
            + ' <a href="javascript:show_all()">Show All</a>'
            + ' <a href="javascript:hide_all()">Hide All</a>'
            + ' <a href="javascript:hide_nick_filter()">(hide this window)</a> '
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

function hide_nick_filter() {
    $('#filterbox').hide();
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

// Summary features
var summary_filter_link = '<a href="javascript:hide_non_summary()">show only summary lines</a>';
var enable_summary_mode_html = ' <a href="javascript:ui_enable_summary_mode()">Enable summary mode</a>';
var summary_mode_html = '<a href="javascript:save_summary_changes()">Save summary changes</a>, <span id="toggle_summary">' + summary_filter_link + '</span> <a href="javascript:disable_summary_mode()">disable summary mode</a>';
$(document).ready(function() {
    disable_summary_mode();
});

function ui_enable_summary_mode() {
    var $s = $('#log th').add($('#log tr'));
    enable_summary_mode($s);
}

function enable_summary_mode($s, force) {
    if (!force && $('.summary').length) {
        $('.summary').show();
        $('#summary_container').html(summary_mode_html);
        return;
    }
    $('#summary_container').html('Loading...');
    var url = IlbotConfig.base_url + 'e/' + IlbotConfig.channel + '/' + IlbotConfig.day + '/summary';
    $.ajax(url, {
        accept: 'application/json',
        success: function(d) {
            $s.filter('th').eq(0).after('<th class="summary">S</th>');
            $s.filter('tr').each(function (idx, e) {
                var id = $(e).find('.time').attr('id');
                if (id) {
                    var i = id.substr(2);
                    var to_insert = '<td class="summary"><input type="checkbox" name="in_summary_' + i + '" class="summary_checkbox" /></td>';
                    $(e).find('.nick').before(to_insert);
                }
                else {
                    $(e).find('.nick').before('<td class="summary" />');
                }

            });
            for (var checked_idx in d) {
                var selector = '#i_' + d[checked_idx];
                $(selector).parent().find('input').attr('checked', 'checked').addClass('originally_checked');
            }
            $('#summary_container').html(summary_mode_html);
            $('input.summary_checkbox').click(function() {
                window.onbeforeunload = function () { return 'You have unsaved changes!' };
            });
            IlbotConfig.in_summary_mode = true;
        }
    });
}
function disable_summary_mode() {
    $('.summary').hide();
    $('#summary_container').html(enable_summary_mode_html);
    IlbotConfig.in_summary_mode = false;
}

function notify(msg) {
    $('#notify').html(msg).fadeIn().delay(5000).fadeOut();
}

function save_summary_changes() {
    var newly_checked = [];
    var was_checked = [];
    $('.originally_checked').each(function(index, element) {
            if (! $(element).is(':checked')) {
                was_checked.push(
                    $(element).attr('name').split('_')[2]
                );
            }
    });
    $('.summary_checkbox:checked').each(function(index, element) {
            if (! $(element).attr('class').match(/originally_checked/)) {
                newly_checked.push(
                    $(element).attr('name').split('_')[2]
                );
            }
    });
    if (was_checked.length != 0 || newly_checked.length != 0) {
        $.post(IlbotConfig.base_url +  "e/summary",
            { check: newly_checked.join('.'), uncheck: was_checked.join('.') },
            function () {
                notify('Summary saved!');

                window.onbeforeunload = null;
            }
        );
    }
    else {
        notify('No changes to save');
    }
}

function hide_non_summary() {
    $('.summary_checkbox:not(:checked)').parents('tr').hide();
    $('#toggle_summary').html('<a href="javascript:show_all_rows()">show all lines</a>');
    $('tr.cont td.nick').css('visibility', 'visible');
}

function show_all_rows() {
    $('.summary_checkbox').parents('tr').show();
    $('#toggle_summary').html(summary_filter_link);
    $('tr.cont td.nick').css('visibility', 'hidden');
}

/* polling */
(function() {
    var is_today = IlbotConfig.still_today;
    IlbotConfig.currently_polling = false;

    function get_id(e) {
        return e.children().first().attr('id');
    }

    IlbotConfig.poll = function poll() {
        if (!is_today) { return }
        if (IlbotConfig.currently_polling) { return; }
        IlbotConfig.currently_polling = true;

        var last_id = get_id($('table#log tr').last()).split('_')[1];
        var url = IlbotConfig.base_url + 'e/' + IlbotConfig.channel + '/' + IlbotConfig.day + '/ajax/' + last_id;
        $.ajax(url, {
            accepts: 'application/json',
            success: function(data) {
                is_today = data.still_today;
                if (!is_today) {
                    $('#poll').hide();
                    $('document').unbind('keydown');
                }
                $('#poll input').blur();
                var $last = $('table#log tr').last();
                $('table#log tr').css('border-bottom-style', 'none');
                $last.css('border-bottom-style', 'solid');
                $last.after(data.text);
                var $newly_loaded = $last.nextAll();
                if (IlbotConfig.in_summary_mode) {
                    enable_summary_mode($newly_loaded, true);
                }
                collapse($newly_loaded);
            },
            complete: function() {
                IlbotConfig.currently_polling = false;
            }
        });
    }
    $(document).ready(function() {
        if (IlbotConfig.still_today) {
            $('#bottom').before(
                '<p id="poll">'
                +    '<input type="button" onclick="IlbotConfig.poll()" value="Look for new lines (r)" /> '
                + '</p>'
            );
        }
        $(document).bind('keydown', 'r', IlbotConfig.poll);
    });
})()

