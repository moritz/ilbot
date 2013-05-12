$(document).ready(function() {
    var last_idx_with_special = -2;
    var collapster;
    $('tr.special.new').each(function (idx, elem) {
        var ids = [$(elem).attr('id')];
        $(elem).nextAll().each(function (i, e) {
            if ($(e).hasClass('special')) {
                $(e).addClass('hidden');
                ids.push($(e).attr('id'));
            }
            else {
                /* abort iteration */
                return false;
            }

        });
        var c = ids.length;
        if (c > 1) {
            $(elem).data('ids', ids);
            $(elem).addClass('hidden');
            var extra_class = 'light';
            if ($(elem).hasClass('dark')) {
                extra_class = 'dark';
            }
            $(elem).before('<tr class="special ' + extra_class + '"><td /> <td /><td class="summary" /><td>' + c + ' more elements. <a href="javascript:show_collpased(\'' + $(elem).attr('id') + '\')">Show/hide.</a></td></tr>');
        }
    });
});

function show_collpased(id) {
    var ids = $('#' + id).data('ids');
    for (i in ids ) {
        $('#' + ids[i]).toggleClass('hidden');
    }
}
