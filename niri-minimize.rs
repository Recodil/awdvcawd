    // win11-shell: кнопка «Свернуть» в заголовке окна. niri сам сворачивать не умеет,
    // поэтому запрос передаётся оболочке: win11-minimize <номер окна>.
    fn minimize_request(&mut self, surface: ToplevelSurface) {
        let Some((mapped, _)) = self
            .niri
            .layout
            .find_window_and_output(surface.wl_surface())
        else {
            return;
        };
        let id = mapped.id().get();
        crate::utils::spawning::spawn(vec![String::from("win11-minimize"), id.to_string()], None);
    }
