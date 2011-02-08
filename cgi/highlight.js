function line_highlight() {
    var hash = window.location.hash;
    $("tr").removeClass("highlight");
    $(hash).parent().addClass("highlight");
}

$(document).ready(function() {
    $(window).bind('hashchange', line_highlight);
    line_highlight();
});
