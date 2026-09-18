import { Nav, PageHeader } from "../../components/ui";

const courses = [
  {
    title: "Mindset",
    audience: "Affiliates",
    price: "₦10,000",
    description: "Build stronger habits and a growth-focused mindset.",
  },
  {
    title: "Career Change",
    audience: "Affiliates",
    price: "₦12,000",
    description: "Learn practical strategies for navigating a career transition.",
  },
  {
    title: "How to Be Smart",
    audience: "Affiliates",
    price: "₦10,000",
    description: "Develop better thinking, learning and decision-making habits.",
  },
  {
    title: "Better Version",
    audience: "Affiliates",
    price: "₦15,000",
    description: "Build systems for personal improvement and consistency.",
  },
  {
    title: "Navigate Human Behaviour",
    audience: "Affiliates",
    price: "₦15,000",
    description: "Understand communication, boundaries and social behaviour.",
  },
  {
    title: "Ghostwriting Mastery",
    audience: "Writers",
    price: "₦10,000",
    description: "Learn the foundations of professional ghostwriting.",
  },
];

export default function CoursesPage() {
  return (
    <main className="page">
      <div className="container">
        <Nav />

        <PageHeader
          eyebrow="Courses Marketplace"
          title="Learn. Create. Grow."
          description="Courses for writers and affiliates, with modules managed through the Breethub platform."
        />

        <div className="grid">
          {courses.map((course) => (
            <article className="glass story-card" key={course.title}>
              <div className="gold">{course.audience}</div>
              <h3 style={{ marginTop: 10 }}>{course.title}</h3>
              <p className="muted">{course.description}</p>

              <div style={{ margin: "18px 0" }}>
                <strong>{course.price}</strong>
              </div>

              <button className="btn btn-primary">View course</button>
            </article>
          ))}
        </div>
      </div>
    </main>
  );
}
