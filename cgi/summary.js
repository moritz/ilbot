var summary_filter_link = '<a href="javascript:hide_non_summary()">show only summary lines</a>';
$(document).ready(function() {
        $('#summary_container').html('<a href="javascript:save_summary_changes()">Save summary changes</a>, <span id="toggle_summary">' + summary_filter_link + '</span>');
});

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
    $('.summary_checkbox:not(:checked)').parent().parent().hide();
    $('#toggle_summary').html('<a href="javascript:show_all_rows()">show all lines</a>');
}

function show_all_rows() {
    $('.summary_checkbox').parent().parent().show();
    $('#toggle_summary').html(summary_filter_link);
}
