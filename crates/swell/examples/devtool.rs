//! This tool is used to exercise swell and system APIs during development.

use std::{future::Future, time::Instant};

use accessibility::{AXUIElement, AXUIElementAttributes};
use core_foundation::{array::CFArray, base::TCFType, dictionary::CFDictionaryRef};
use core_graphics::{
    display::{CGDisplayBounds, CGMainDisplayID},
    window::{kCGNullWindowID, kCGWindowListOptionOnScreenOnly, CGWindowListCopyWindowInfo},
};
use icrate::{AppKit::NSScreen, Foundation::MainThreadMarker};
use structopt::StructOpt;
use tokio::sync::mpsc;

use swell::{
    app,
    screen::{self, ScreenCache},
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

#[derive(StructOpt)]
pub struct Opt {
    pub bundle: Option<String>,
    pub resize: Option<String>,
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    tracing_subscriber::registry()
        .with(EnvFilter::from_default_env())
        .with(tracing_tree::HierarchicalLayer::default())
        .init();
    let opt = Opt::from_args();
    //time("accessibility serial", || get_windows_with_ax(&opt, true)).await;
    time("core-graphics", || get_windows_with_cg(&opt, true)).await;
    time("accessibility", || get_windows_with_ax(&opt, false, true)).await;
    time("core-graphics second time", || {
        get_windows_with_cg(&opt, false)
    })
    .await;
    time("accessibility second time", || {
        get_windows_with_ax(&opt, false, false)
    })
    .await;
    get_apps(&opt);

    println!("Current space: {:?}", screen::diagnostic::cur_space());
    println!("Visible spaces: {:?}", screen::diagnostic::visible_spaces());
    println!("All spaces: {:?}", screen::diagnostic::all_spaces());
    println!("{:?}", screen::diagnostic::managed_display_spaces());

    dbg!(screen::diagnostic::managed_displays());
    let screens = NSScreen::screens(MainThreadMarker::new().unwrap());
    let frames: Vec<_> = screens.iter().map(|screen| screen.visibleFrame()).collect();
    println!("NSScreen sizes: {frames:?}");

    println!();
    let mut sc = ScreenCache::new(MainThreadMarker::new().unwrap());
    println!("Frames: {:?}", sc.update_screen_config());
    println!("Spaces: {:?}", sc.get_screen_spaces());
}

async fn get_windows_with_cg(_opt: &Opt, print: bool) {
    let windows: CFArray<CFDictionaryRef> = unsafe {
        CFArray::wrap_under_get_rule(CGWindowListCopyWindowInfo(
            kCGWindowListOptionOnScreenOnly,
            kCGNullWindowID,
        ))
    };
    if print {
        println!("{windows:?}");
    }
    let display_id = unsafe { CGMainDisplayID() };
    let screen = unsafe { CGDisplayBounds(display_id) };
    println!("main display = {screen:?}");
}

async fn get_windows_with_ax(opt: &Opt, serial: bool, print: bool) {
    let (sender, mut receiver) = mpsc::unbounded_channel();
    for (pid, bundle_id) in app::running_apps(opt.bundle.clone()) {
        let sender = sender.clone();
        let task = move || {
            let app = AXUIElement::application(pid);
            let windows = get_windows_for_app(app);
            sender.send((bundle_id, windows)).unwrap()
        };
        if serial {
            task();
        } else {
            tokio::task::spawn_blocking(task);
        }
    }
    drop(sender);
    while let Some((info, windows)) = receiver.recv().await {
        //println!("{info:?}");
        match windows {
            Ok(windows) => {
                if print {
                    for win in windows {
                        println!("{win:?} from {}", info.bundle_id.as_deref().unwrap_or("?"));
                    }
                }
            }
            Err(_) => (), //println!("  * Error reading windows: {err:?}"),
        }
    }
}

fn get_windows_for_app(app: AXUIElement) -> Result<Vec<app::WindowInfo>, accessibility::Error> {
    let Ok(windows) = &app.windows() else {
        return Err(accessibility::Error::NotFound);
    };
    windows.into_iter().map(|win| app::WindowInfo::try_from(&*win)).collect()
}

fn get_apps(opt: &Opt) {
    for (pid, _bundle_id) in app::running_apps(opt.bundle.clone()) {
        let app = AXUIElement::application(pid);
        println!("{app:#?}");
    }
}

async fn time<O, F: Future<Output = O>>(desc: &str, f: impl FnOnce() -> F) -> O {
    let start = Instant::now();
    let out = f().await;
    let end = Instant::now();
    println!("{desc} took {:?}", end - start);
    out
}
