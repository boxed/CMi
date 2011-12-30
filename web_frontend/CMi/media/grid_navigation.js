var grid = {};
var current_pos_x = 0;
var current_pos_y = 0;

function init_navigation() {
    grid = {};
    current_pos_x = 0;
    current_pos_y = 0;
    // we start out with grid[y][x] style notation for convenience...
    function get_next_x(y) {
        if (!(y in grid)) {
            grid[y] = {};
        }
        for (var x = 0; ; x++) {
            if (!(x in grid[y])) {
                return x;
            }
        }
    }
    $('.tiles.display tr').each(function(y, row){
        $('td', row).each(function(cell_index, c){
            var cell = $(c);
            var x = get_next_x(y);
            if (cell.hasClass('tile')) {
                // set a cell ref at this position
                grid[y][x] = c;
                var colspan = parseInt(cell.attr('colspan')) || 1;
                var rowspan = parseInt(cell.attr('rowspan')) || 1;
                for (var _x = 0; _x != colspan; _x++) {
                    for (var _y = 0; _y != rowspan; _y++) {
                        if (!(_y+y in grid)) {
                            grid[_y+y] = {};
                        }
                        grid[_y+y][_x+x] = c;
                    }
                }
            }
            else {
                // set null at this position
                grid[y][x] = null;
            }
        });
    });
    /*
     // debug code
     for (var y in grid) {
     var line = '';
     for (var x = 0; x != 6; x++) {
     line += '\t'+$(grid[y][x]).html();
     }
     console.log(''+y+line);
     }*/
    // flip axis of grid so we get grid[x][y] instead of grid[y][x]
    var tmp = grid;
    grid = new Array();
    for (var y = 0; ; y++) {
        if (!(y in tmp)) {
            break;
        }
        for (var x = 0; ; x++) {
            if (!(x in tmp[y])) {
                break;
            }
            if (x >= grid.length) {
                grid.push(new Array());
            }
            grid[x][y] = tmp[y][x];
        }
    }
    if (grid.length == 0) {
        return;
    }
    // trim grid of non-gui columns
    for (x = grid.length-1; x >= 0; x--) {
        var throw_col = true;
        for (y in grid[x]) {
            if (grid[x][y]) {
                throw_col = false;
                break;
            }
        }
        if (throw_col) {
            grid.splice(x, 1);
        }
    }
    // trim grid of non-gui rows
    for (y = grid[0].length-1; y >= 0; y--) {
        var throw_row = true;
        for (x = grid.length-1; x >= 0; x--) {
            if (grid[x][y]) {
                throw_row = false;
                break;
            }
        }
        if (throw_row) {
            for (x = grid.length-1; x >= 0; x--) {
                grid[x].splice(y, 1);
            }
        }
    }
    // set initial focus
    $(grid[current_pos_x][current_pos_y]).addClass('focus');
}

function set_focus(x, y) {
    if (x >= 0 && x < grid.length && y >= 0 && y < grid[x].length) {
        if (grid[current_pos_x][current_pos_y] == grid[x][y] || grid[x][y] == null) {
            var diff_x = x-current_pos_x;
            var diff_y = y-current_pos_y;
            if (diff_x != 0 && diff_y != 0) {
                set_focus(x+diff_x, y+diff_y);
            }
            return;
        }

        $(grid[current_pos_x][current_pos_y]).removeClass('focus');
        current_pos_x = x;
        current_pos_y = y;
        $(grid[x][y]).addClass('focus');
    }
}

function current_cell() {
    if (current_pos_x >= 0 && current_pos_x < grid.length && current_pos_y >= 0 && current_pos_y < grid[current_pos_x].length) {
        return grid[current_pos_x][current_pos_y];
    }
    return false;
}

function get_x_y_of(cell) {
    for (var x = 0; x != grid.length; x++) {
        for (var y = 0; y != grid[x].length; y++) {
            if (cell == grid[x][y]) {
                return [x, y]
            }
        }
    }
}

$(document).ready(function(){
    init_navigation();

    $(document).keydown(function(e) {
        switch (e.keyCode) {
            case 39: // right arrow
                set_focus(current_pos_x+1, current_pos_y);
                e.preventDefault();
                return false;
            case 40: // down arrow
                set_focus(current_pos_x, current_pos_y+1);
                e.preventDefault();
                return false;
            case 37: // left arrow
                set_focus(current_pos_x-1, current_pos_y);
                e.preventDefault();
                return false;
            case 38: // up arrow
                set_focus(current_pos_x, current_pos_y-1);
                e.preventDefault();
                return false;
            default:
                break;
        }
        return true;
    });
});