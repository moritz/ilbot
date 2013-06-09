var summary_filter_link = '<a href="javascript:hide_non_summary()">show only summary lines</a>';
var enable_summary_mode_html = ' <a href="javascript:enable_summary_mode()">Enable summary mode</a>';
var summary_mode_html = '<a href="javascript:save_summary_changes()">Save summary changes</a>, <span id="toggle_summary">' + summary_filter_link + '</span> <a href="javascript:disable_summary_mode()">disable summary mode</a>';
$(document).ready(function() {
    disable_summary_mode();
});

function enable_summary_mode() {
    if ($('.summary').length) {
        $('.summary').show();
        $('#summary_container').html(summary_mode_html);
        return;
    }
    $('#summary_container').html('Loading...');
    var url = IlbotConfig.base_url + 'e/' + IlbotConfig.channel + '/' + IlbotConfig.day + '/summary';
    $.ajax(url, {
        accept: 'application/json',
        success: function(d) {
            $('#log th').eq(0).after('<th class="summary">S</th>');
            $('#log tr').each(function (idx, e) {
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
        }
    });
}
function disable_summary_mode() {
    $('.summary').hide();
    $('#summary_container').html(enable_summary_mode_html);
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
        $.post(IlbotConfig.base_url +  "e/summary", { check: newly_checked.join('.'), uncheck: was_checked.join('.') } );
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
