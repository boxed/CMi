var transitionDuration = 700;
var menu_history = [];
var menu_history_position = [];
var menu_history_scroll_position = [];
var current_pos_x = 0;
var current_pos_y = 0;
var prevent_refresh = false;

function pad(number, length) {
    var str = '' + number;
    while (str.length < length) {
        str = '0' + str;
    }
    return str;
}

function get_tiles() {
    var tiles = $('.display td');
    if (tiles.length == 0) {
        tiles = $('.display .fullscreen');
    }
    return tiles;
}

function flip_in(selector, new_page) { // new_page defaults to true
    new_page = typeof(new_page) != 'undefined' ? new_page: true;

    var foo = $(selector);

    foo.addClass('display');
    setup_menu();
    show_hide_back_button();

    foo.css({'z-index':'0'});
    var tiles = get_tiles();
    prepare_tiles(tiles);
    if (new_page) {
        tiles.css({
            'z-index': '5000',
            webkitTransform: "translate3d(0,0,0) rotateY(0deg)",
            webkitTransitionDuration: transitionDuration+'ms'
        });
        tiles.each(function(i) {
            $(this).addClass('flip_'+i);
        });
        foo.addClass('started');
    }
    else {
        tiles.css({webkitTransform: "translate3d(0,0,0) rotateY(0deg)"});
    }
    $('.header.display').css('opacity', 1);
    if (new_page) {
        current_pos_x = 0;
        current_pos_y = 0;
    }
    init_navigation();
}

function flip_out() {
    var tile_container = $('.tiles.display');
    tile_container.css({'z-index':'100'});
    var header = $('.header.display');
    header.css('opacity', 0);
    header.removeClass('display');
    var tiles = get_tiles();
    var _i = 0;
    tiles.css({
        'z-index': '5000',
        webkitTransform: "translate3d(0,0,0) rotateY(-90deg)",
        webkitTransitionDuration: transitionDuration+'ms'
    });
    tiles.each(function() {
        $(this).css({
            webkitTransitionDelay: Math.min(_i, 10) * 80 + "ms"
        });
        _i++;
    });
    tiles.unbind('hover');
    tiles.unbind('click');
    setTimeout(function() {
        tiles.remove();
        header.remove();
        tile_container.remove();
    }, transitionDuration*_i);
    $('.display').removeClass('display');
}

function refresh() {
    if (!prevent_refresh) {
        var url = menu_history[menu_history.length-1];
        $.ajax({
               url: url,
               data: {ajax: 'True'},
               success: function(data) {
                   $('.header').remove();
                   $('table').remove();
                   var d = $(data);
                   $('body').append(d);
                   flip_in(d, false);
               }
        });
    }
}

function handle_response(data, url) {
    if (data == ':nothing') {
    }
    else if (data == ':refresh') {
        refresh();
    }
    else if (data == ':back') {
        back();
    }
    else if (data == ':back2') {
        back(2);
    }
    else {
        var d = $(data);
        $('body').append(d);
        flip_in(d);
    }
}

function go() {
    var item = $(grid[current_pos_x][current_pos_y]);
    item.addClass('pressed');
    if (item.attr('command')) {
        var command = item.attr('command');
        var js = 'javascript:';
        if (command.slice(0, js.length) === js) {
            eval(command.slice(js.length));
        }
        else {
            $.ajax({
                url: command,
                data: {ajax: 'True'},
                success: function(data) {
                    handle_response(data, url);
                }
            });
        }
    }
    else if (item.attr('url')) {
        var url = item.attr('url');
        if (url == ':back') {
            back();
        }
        else {
            if (menu_history[menu_history.length-1] == url) {
                fail_history_corrupted();
            }
            menu_history.push(url);
            menu_history_position.push([current_pos_x, current_pos_y]);
            menu_history_scroll_position.push($('body').scrollTop());
            flip_out();
            $.ajax({
                url: url,
                data: {ajax: 'True'},
                success: function(data) {
                    handle_response(data, url);
                }
            });
        }
    }
}

function del() {
    var item = $(grid[current_pos_x][current_pos_y]);
    if (item.attr('url')) {
        var url = item.attr('url');
        $.ajax({
            url: url+'ended',
            data: {ajax: 'True'},
            success: function(data) {
                handle_response(data, url);
            }
        });
    }
}

function do_hover() {
    var xy = get_x_y_of(this);
    if (xy) {
        $('.focus').removeClass('focus');
        current_pos_x = xy[0];
        current_pos_y = xy[1];
        $(grid[current_pos_x][current_pos_y]).addClass('focus');
    }
    else {
        console.log('hover failed '+this);
    }
}

function setup_menu() {
    $('.tile').click(function() {
        if ($(this).attr('url')) {
            go();
        }
    });
    $('td.tile').hover(do_hover);
}

function back(steps) {
    if (menu_history.length > 1) {
        flip_out();
        steps = typeof(steps) != 'undefined' ? steps: 1;
        for (var i = 0; i != steps && menu_history.length > 1; i++) {
            menu_history.pop(); // remove current url from history
        }
        if (menu_history.length > 0) {
            var url = menu_history[menu_history.length-1];
            $.ajax({
                url: url,
                data: {ajax: 'True'},
                success: function(data) {
                    // pop history a second time because handle_response will fill it in again
                    var pos = menu_history_position.pop();
                    handle_response(data, url);
                    set_focus(pos[0], pos[1]);
                    $('body').scrollTop(menu_history_scroll_position.pop())
                }
            });
            show_hide_back_button();
        }
    }
}

function show_hide_back_button() {
    if (menu_history.length <= 1) {
        jQuery('#back_link').animate({opacity: '0'}, {duration: 300});
    }
    else {
        jQuery('#back_link').animate({opacity: '1'}, {duration: 300});
    }
}

function search_for_new_files() {
    $.ajax({
           url: '/search_for_new_files/',
           data: {ajax: 'True'},
           success: function(data) {
                handle_response(data);
            }
    });
}

$(document).ready(function (){
    menu_history.push('/');
    flip_in('table');
                  
    document.body.style.zoom = 1;

    $(document).keyup(function(e) {e.preventDefault(); return false;});
    $(document).keydown(function(e) {
        switch (e.keyCode) {
            case 27: // esc
            case 8: // backspace
                back();
                e.preventDefault();
                return false;
            case 13: // return
                go();
                e.preventDefault();
                return false;
            case 'D'.charCodeAt(0):
                del();
                e.preventDefault();
                return false;
            case 9: // tab
            case 'R'.charCodeAt(0):
                refresh();
                e.preventDefault();
                return false;
            case 107: // '+'
                document.body.style.zoom = parseFloat(document.body.style.zoom) + 0.1;
                return false;
            case 109: // '-'
                document.body.style.zoom = parseFloat(document.body.style.zoom) - 0.1;
                return false;
            case '0'.charCodeAt(0):
                document.body.style.zoom = 1;
                return false;
            default:
                break;
        }
        return true;
    });

    setTimeout(function() {
        update_clock();
    }, 100);
});

function update_clock() {
    var d = new Date();
    $('#clock').html(d.getHours()+':'+pad(d.getMinutes(), 2));
    setTimeout(update_clock, 500);

    /*$.ajax({
        url: '/code_changed/',
        data: {ajax: 'True'},
        success: function(data) {
            if (parseInt(data)) {
                refresh();
            }
        }
    });*/
}

function prepare_tiles(tiles) {
    tiles = $(tiles);
    var tilePosX = 0, tilePosY = 0;
    tiles.css({
        opacity: 1
    });
    tiles.each(
        function(_i) {
            var _me = $(this);
            var origin = -(_me.offset().left);
            _me.css({webkitTransformOriginX: origin + "px"});
        }).click(function() {
            $(".tiles .selected").removeClass("selected");
            $(this).addClass("selected");
        });
}
