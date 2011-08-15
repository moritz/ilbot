$(document).ready(function() {
        $('#summary_container').html('<a href="javascript:save_summary_changes()">Save summary changes</a>');

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
}
