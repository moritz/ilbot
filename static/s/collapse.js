$(document).ready(function() {
    var hash = window.location.hash;
    var uncollapse;

    $('tr.special.new').each(function (idx, elem) {
        var ids = [$(elem).attr('id')];
        $(elem).nextAll().each(function (i, e) {
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
            $(elem).data('ids', ids);
            $(elem).addClass('hidden');
            var extra_class = 'light';
            if ($(elem).hasClass('dark')) {
                extra_class = 'dark';
            }
            $(elem).before('<tr class="special ' + extra_class + '"><td class="nick" /> <td /><td>' + c + ' more elements. <a href="javascript:show_collapsed(\'' + $(elem).attr('id') + '\')">Show/hide.</a></td></tr>');
	   if (uncollapse) {
                show_collapsed(uncollapse);
           }
        }
    });
});

function show_collapsed(id) {
    var ids = $('#' + id).data('ids');
    for (i in ids ) {
        $('#' + ids[i]).toggleClass('hidden');
    }
}
