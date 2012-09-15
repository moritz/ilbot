var summary_filter_link = '<a href="javascript:hide_non_summary()">show only summary lines</a>';
var enable_summary_mode_html = '<a href="javascript:enable_summary_mode()">Enable summary mode</a>';
$(document).ready(function() {
    disable_summary_mode();
});

function enable_summary_mode() {
        $('#summary_container').html('<a href="javascript:save_summary_changes()">Save summary changes</a>, <span id="toggle_summary">' + summary_filter_link + '</span> <a href="javascript:disable_summary_mode()">disable summary mode</a>');
        $('.summary').show();
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
        $.post("/save_summary.pl", { check: newly_checked.join('.'), uncheck: was_checked.join('.') } );
    }
}

function hide_non_summary() {
    $('.summary_checkbox:not(:checked)').parents('tr').hide();
    $('#toggle_summary').html('<a href="javascript:show_all_rows()">show all lines</a>');
}

function show_all_rows() {
    $('.summary_checkbox').parents('tr').show();
    $('#toggle_summary').html(summary_filter_link);
}
