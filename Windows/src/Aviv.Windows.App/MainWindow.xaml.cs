using System.ComponentModel;
using System.Windows.Input;
using Aviv.Windows.App.Controls;
using Aviv.Windows.App.Services;
using Aviv.Windows.App.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace Aviv.Windows.App;

public sealed partial class MainWindow : Window
{
    private const VirtualKey BacktickKey = (VirtualKey)192;
    private readonly Grid rootGrid = new();
    private readonly EditorDocumentViewModel viewModel;
    private readonly MarkdownEditorView editorView;
    private bool syncingFromViewModel;

    public MainWindow()
    {
        DiagnosticLog.Write("MainWindow constructor starting.");
        Content = rootGrid;
        rootGrid.Background = ResourceBrush("AvivBackgroundBrush");
        DiagnosticLog.Write("MainWindow root grid created.");

        viewModel = new EditorDocumentViewModel(new MarkdownFileService(this));
        rootGrid.DataContext = viewModel;
        DiagnosticLog.Write("MainWindow DataContext assigned.");

        editorView = new MarkdownEditorView();
        BuildLayout();
        DiagnosticLog.Write("MainWindow layout built.");

        editorView.LoadMarkdown(viewModel.Markdown);
        DiagnosticLog.Write("Initial Markdown loaded into editor.");

        viewModel.PropertyChanged += OnViewModelPropertyChanged;
        viewModel.EditRequested += action => editorView.ApplyEditAction(action);
        viewModel.EditorCommandRequested += command => editorView.PerformEditorCommand(command);
        viewModel.ViewScaleChanged += scale => editorView.SetViewScale(scale);
        InstallKeyboardAccelerators();
        editorView.MarkdownChanged += markdown =>
        {
            if (syncingFromViewModel)
            {
                return;
            }

            viewModel.UpdateFromEditor(markdown);
        };
        DiagnosticLog.Write("MainWindow constructor completed.");
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName != nameof(EditorDocumentViewModel.Markdown) || editorView.Markdown == viewModel.Markdown)
        {
            return;
        }

        syncingFromViewModel = true;
        editorView.LoadMarkdown(viewModel.Markdown);
        syncingFromViewModel = false;
    }

    private void BuildLayout()
    {
        rootGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var menuBar = new MenuBar
        {
            Background = ResourceBrush("AvivChromeBrush")
        };
        Grid.SetRow(menuBar, 0);
        rootGrid.Children.Add(menuBar);

        menuBar.Items.Add(Menu("File",
            Item("New", viewModel.NewDocumentCommand),
            Item("New Tab", viewModel.NewTabCommand),
            Item("Open...", viewModel.OpenDocumentCommand),
            Separator(),
            Item("Close", viewModel.CloseDocumentCommand),
            Separator(),
            Item("Save", viewModel.SaveDocumentCommand),
            Item("Save As...", viewModel.SaveDocumentAsCommand),
            Item("Revert to Saved", viewModel.RevertDocumentCommand),
            Separator(),
            Item("Page Setup...", viewModel.PageSetupCommand),
            Item("Print...", viewModel.PrintDocumentCommand)));

        menuBar.Items.Add(Menu("Edit",
            Item("Undo", viewModel.UndoCommand),
            Item("Redo", viewModel.RedoCommand),
            Separator(),
            Item("Cut", viewModel.CutCommand),
            Item("Copy", viewModel.CopyCommand),
            Item("Paste", viewModel.PasteCommand),
            Item("Paste and Match Style", viewModel.PastePlainTextCommand),
            Separator(),
            Item("Select All", viewModel.SelectAllCommand),
            Separator(),
            Item("Find...", viewModel.FindCommand),
            Item("Find and Replace...", viewModel.FindAndReplaceCommand),
            Item("Find Next", viewModel.FindNextCommand),
            Item("Find Previous", viewModel.FindPreviousCommand)));

        menuBar.Items.Add(Menu("View",
            Item("Actual Size", viewModel.ResetTextSizeCommand),
            Item("Zoom In", viewModel.IncreaseTextSizeCommand),
            Item("Zoom Out", viewModel.DecreaseTextSizeCommand)));

        menuBar.Items.Add(Menu("Format",
            Item("Bold", viewModel.ToggleBoldCommand),
            Item("Italic", viewModel.ToggleItalicCommand),
            Item("Code", viewModel.ToggleCodeCommand),
            Separator(),
            Item("Heading 1", viewModel.Heading1Command),
            Item("Heading 2", viewModel.Heading2Command)));

        menuBar.Items.Add(Menu("Window",
            Item("Show Previous Tab", viewModel.ShowPreviousTabCommand),
            Item("Show Next Tab", viewModel.ShowNextTabCommand),
            Item("Move Tab to New Window", viewModel.MoveTabToNewWindowCommand),
            Item("Merge All Windows", viewModel.MergeAllWindowsCommand)));

        Grid.SetRow(editorView, 1);
        rootGrid.Children.Add(editorView);
    }

    private static MenuBarItem Menu(string title, params MenuFlyoutItemBase[] items)
    {
        var menu = new MenuBarItem { Title = title };
        foreach (var item in items)
        {
            menu.Items.Add(item);
        }

        return menu;
    }

    private static MenuFlyoutItem Item(string text, ICommand command)
    {
        return new MenuFlyoutItem
        {
            Text = text,
            Command = command
        };
    }

    private static MenuFlyoutSeparator Separator() => new();

    private static Microsoft.UI.Xaml.Media.Brush ResourceBrush(string key)
    {
        return key switch
        {
            "AvivChromeBrush" => SolidBrush(0xDD, 0xFD, 0xFE, 0xFF),
            "AvivChromeStrokeBrush" => SolidBrush(0x1F, 0x6B, 0x72, 0x80),
            _ => SolidBrush(0xFF, 0xFB, 0xFC, 0xFD)
        };
    }

    private static Microsoft.UI.Xaml.Media.SolidColorBrush SolidBrush(byte a, byte r, byte g, byte b)
    {
        return new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(a, r, g, b));
    }

    private void InstallKeyboardAccelerators()
    {
        AddAccelerator(VirtualKey.N, VirtualKeyModifiers.Control, () => viewModel.NewDocumentCommand.Execute(null));
        AddAccelerator(VirtualKey.T, VirtualKeyModifiers.Control, () => viewModel.NewTabCommand.Execute(null));
        AddAccelerator(VirtualKey.O, VirtualKeyModifiers.Control, () => viewModel.OpenDocumentCommand.Execute(null));
        AddAccelerator(VirtualKey.W, VirtualKeyModifiers.Control, () => viewModel.CloseDocumentCommand.Execute(null));
        AddAccelerator(VirtualKey.S, VirtualKeyModifiers.Control, () => viewModel.SaveDocumentCommand.Execute(null));
        AddAccelerator(VirtualKey.S, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => viewModel.SaveDocumentAsCommand.Execute(null));
        AddAccelerator(VirtualKey.P, VirtualKeyModifiers.Control, () => viewModel.PrintDocumentCommand.Execute(null));
        AddAccelerator(VirtualKey.Number0, VirtualKeyModifiers.Control, () => viewModel.ResetTextSizeCommand.Execute(null));
        AddAccelerator(VirtualKey.Add, VirtualKeyModifiers.Control, () => viewModel.IncreaseTextSizeCommand.Execute(null));
        AddAccelerator(VirtualKey.Subtract, VirtualKeyModifiers.Control, () => viewModel.DecreaseTextSizeCommand.Execute(null));
        AddAccelerator(VirtualKey.B, VirtualKeyModifiers.Control, () => viewModel.ToggleBoldCommand.Execute(null));
        AddAccelerator(VirtualKey.I, VirtualKeyModifiers.Control, () => viewModel.ToggleItalicCommand.Execute(null));
        AddAccelerator(BacktickKey, VirtualKeyModifiers.Control, () => viewModel.ToggleCodeCommand.Execute(null));
        AddAccelerator(VirtualKey.Number1, VirtualKeyModifiers.Control, () => viewModel.Heading1Command.Execute(null));
        AddAccelerator(VirtualKey.Number2, VirtualKeyModifiers.Control, () => viewModel.Heading2Command.Execute(null));
        AddAccelerator(VirtualKey.Tab, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => viewModel.ShowPreviousTabCommand.Execute(null));
        AddAccelerator(VirtualKey.Tab, VirtualKeyModifiers.Control, () => viewModel.ShowNextTabCommand.Execute(null));
        AddAccelerator(VirtualKey.Z, VirtualKeyModifiers.Control, () => viewModel.UndoCommand.Execute(null));
        AddAccelerator(VirtualKey.Z, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => viewModel.RedoCommand.Execute(null));
        AddAccelerator(VirtualKey.X, VirtualKeyModifiers.Control, () => viewModel.CutCommand.Execute(null));
        AddAccelerator(VirtualKey.C, VirtualKeyModifiers.Control, () => viewModel.CopyCommand.Execute(null));
        AddAccelerator(VirtualKey.V, VirtualKeyModifiers.Control, () => viewModel.PasteCommand.Execute(null));
        AddAccelerator(VirtualKey.A, VirtualKeyModifiers.Control, () => viewModel.SelectAllCommand.Execute(null));
        AddAccelerator(VirtualKey.F, VirtualKeyModifiers.Control, () => viewModel.FindCommand.Execute(null));
        AddAccelerator(VirtualKey.F, VirtualKeyModifiers.Control | VirtualKeyModifiers.Menu, () => viewModel.FindAndReplaceCommand.Execute(null));
        AddAccelerator(VirtualKey.G, VirtualKeyModifiers.Control, () => viewModel.FindNextCommand.Execute(null));
        AddAccelerator(VirtualKey.G, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => viewModel.FindPreviousCommand.Execute(null));
    }

    private void AddAccelerator(VirtualKey key, VirtualKeyModifiers modifiers, Action action)
    {
        var accelerator = new KeyboardAccelerator
        {
            Key = key,
            Modifiers = modifiers
        };
        accelerator.Invoked += (_, args) =>
        {
            action();
            args.Handled = true;
        };
        rootGrid.KeyboardAccelerators.Add(accelerator);
    }
}
