//! This tool is used to exercise swell and system APIs during development.

use swell::space;

fn main() {
    let space = space::cur_space();
    println!("Current space: {space:?}");
}
