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
    private readonly MarkdownEditorView? editorView;
    private bool syncingFromViewModel;

    public MainWindow()
    {
        DiagnosticLog.Write("MainWindow constructor starting.");
        Content = rootGrid;
        Title = "Aviv";
        rootGrid.Background = ResourceBrush("AvivBackgroundBrush");
        rootGrid.Loaded += (_, _) => DiagnosticLog.Write("MainWindow root grid loaded.");
        DiagnosticLog.Write("MainWindow root grid created.");

        viewModel = new EditorDocumentViewModel(new MarkdownFileService(this));
        rootGrid.DataContext = viewModel;
        DiagnosticLog.Write("MainWindow DataContext assigned.");

        if (!UseSafeVerifierEditor())
        {
            editorView = new MarkdownEditorView();
        }

        BuildLayout();
        DiagnosticLog.Write("MainWindow layout built.");

        if (editorView is not null)
        {
            editorView.LoadMarkdown(viewModel.Markdown);
            DiagnosticLog.Write("Initial Markdown loaded into editor.");
        }
        else
        {
            DiagnosticLog.Write("Safe verifier editor loaded.");
        }

        viewModel.PropertyChanged += OnViewModelPropertyChanged;
        if (editorView is not null)
        {
            viewModel.EditRequested += action => editorView.ApplyEditAction(action);
            viewModel.EditorCommandRequested += command => editorView.PerformEditorCommand(command);
            viewModel.ViewScaleChanged += scale => editorView.SetViewScale(scale);
            editorView.MarkdownChanged += markdown =>
            {
                if (syncingFromViewModel)
                {
                    return;
                }

                viewModel.UpdateFromEditor(markdown);
            };
        }

        InstallKeyboardAccelerators();
        DiagnosticLog.Write("MainWindow constructor completed.");
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (editorView is null ||
            args.PropertyName != nameof(EditorDocumentViewModel.Markdown) ||
            editorView.Markdown == viewModel.Markdown)
        {
            return;
        }

        syncingFromViewModel = true;
        editorView.LoadMarkdown(viewModel.Markdown);
        syncingFromViewModel = false;
    }

    private void BuildLayout()
    {
        if (editorView is null)
        {
            rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            rootGrid.Children.Add(SafeVerifierEditor());
            return;
        }

        rootGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var toolbar = Toolbar();
        Grid.SetRow(toolbar, 0);
        rootGrid.Children.Add(toolbar);

        Grid.SetRow(editorView, 1);
        rootGrid.Children.Add(editorView);
    }

    private TextBox SafeVerifierEditor()
    {
        return new TextBox
        {
            AcceptsReturn = true,
            BorderThickness = new Thickness(0),
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Segoe UI"),
            FontSize = 17,
            Padding = new Thickness(64, 72, 122, 52),
            Text = viewModel.Markdown,
            TextWrapping = TextWrapping.Wrap
        };
    }

    private static bool UseSafeVerifierEditor()
    {
        return string.Equals(Environment.GetEnvironmentVariable("AVIV_SAFE_EDITOR"), "1", StringComparison.Ordinal);
    }

    private StackPanel Toolbar()
    {
        var toolbar = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Padding = new Thickness(10, 7, 10, 7),
            Spacing = 6,
            Background = ResourceBrush("AvivChromeBrush")
        };

        toolbar.Children.Add(ToolButton("New", viewModel.NewDocumentCommand));
        toolbar.Children.Add(ToolButton("Open", viewModel.OpenDocumentCommand));
        toolbar.Children.Add(ToolButton("Save", viewModel.SaveDocumentCommand));
        toolbar.Children.Add(ToolButton("Undo", viewModel.UndoCommand));
        toolbar.Children.Add(ToolButton("Redo", viewModel.RedoCommand));
        toolbar.Children.Add(ToolButton("B", viewModel.ToggleBoldCommand));
        toolbar.Children.Add(ToolButton("I", viewModel.ToggleItalicCommand));
        toolbar.Children.Add(ToolButton("Code", viewModel.ToggleCodeCommand));
        toolbar.Children.Add(ToolButton("H1", viewModel.Heading1Command));
        toolbar.Children.Add(ToolButton("H2", viewModel.Heading2Command));
        toolbar.Children.Add(ToolButton("-", viewModel.DecreaseTextSizeCommand));
        toolbar.Children.Add(ToolButton("+", viewModel.IncreaseTextSizeCommand));
        return toolbar;
    }

    private static Button ToolButton(string text, ICommand command)
    {
        return new Button
        {
            Content = text,
            Command = command,
            FontSize = 12,
            MinHeight = 30,
            MinWidth = 38,
            Padding = new Thickness(10, 3, 10, 4)
        };
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
        return new Microsoft.UI.Xaml.Media.SolidColorBrush(global::Windows.UI.Color.FromArgb(a, r, g, b));
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
